defmodule TypeCheck.Internals.PreExpander do
  @moduledoc false
  # Rewrites a typecheck-AST
  # to replace all Kernel.SpecialForms
  # with alternatives that are not 'special'
  # that e.g. are function calls to functions in `TypeCheck.Builtin`.
  def rewrite(ast, env, options) do
    builtin_imports = env.functions[TypeCheck.Builtin] || []
    ast
    |> Macro.expand(env)
    |> TypeCheck.Internals.Overrides.rewrite_if_override(options.overrides, env)
    |> case do
      ast = {:lazy_explicit, meta, args}  ->
        if {:lazy_explicit, 3} in builtin_imports do
          ast
        else
          {:lazy_explicit, meta, Enum.map(args, &rewrite(&1, env, options))}
        end

      ast = {:literal, meta, [value]} ->
        # Do not expand internals of `literal`.
        # Even if it contains fancy syntax
        # like ranges
        if {:literal, 1} in builtin_imports do
          ast
        else
          {:literal, meta, [rewrite(value, env, options)]}
        end
      ast = {:tuple, meta, [value]} ->
        if {:tuple, 1} in builtin_imports do
          ast
        else
          {:tuple, meta, [rewrite(value, env, options)]}
        end

      ast = {:impl, meta, [module]} ->
         # Do not expand arguments to `impl/1` further
         if {:impl, 1} in builtin_imports do
           ast
         else
           {:impl, meta, [rewrite(module, env, options)]}
         end


      ast = {:&, _, _args} ->
        # Do not expand inside captures
        ast

      x when is_integer(x) or is_float(x) or is_atom(x) or is_bitstring(x) ->
        quote generated: true, location: :keep do
          TypeCheck.Builtin.literal(unquote(x))
        end

      list when is_list(list) ->
        rewritten_values =
          list
          |> Enum.map(&rewrite(&1, env, options))

        quote generated: true, location: :keep do
          TypeCheck.Builtin.fixed_list(unquote(rewritten_values))
        end

      {:|, _, [lhs, rhs]} ->
        quote generated: true, location: :keep do
          TypeCheck.Builtin.one_of(unquote(rewrite(lhs, env, options)), unquote(rewrite(rhs, env, options)))
        end

      ast = {:%{}, _, fields} ->
        rewrite_map_or_struct(fields, ast, env, options)

      {:%, _, [struct_name, {:%{}, _, fields}]} ->
        rewrite_struct(struct_name, fields, env, options)

      {:"::", _, [{name, _, atom}, type_ast]} when is_atom(atom) ->
        quote generated: true, location: :keep do
          TypeCheck.Builtin.named_type(unquote(name), unquote(rewrite(type_ast, env, options)))
        end

      ast = {:when, _, [_type, list]} when is_list(list) ->
        raise ArgumentError, """
        Unsupported `when` with keyword arguments in the type description `#{Macro.to_string(ast)}`

        TypeCheck currently does not allow the `function(foo, bar) :: foo | bar when foo: some_type(), bar: other_type()` syntax.
        Instead, define `foo` and `bar` as separate types and refer to those definitions.

        For instance:

        ```
        type foo :: some_type()
        type bar :: other_type()
        spec function(foo, bar) :: foo | bar
        ```
        """

      {:when, _, [type, guard]} ->
        quote generated: true, location: :keep do
          TypeCheck.Builtin.guarded_by(unquote(rewrite(type, env, options)), unquote(Macro.escape(guard)))
        end

      {:{}, _, elements} ->
        rewrite_tuple(elements, env, options)

      {left, right} ->
        rewrite_tuple([left, right], env, options)

      orig = {variable, meta, atom} when is_atom(atom) ->
        # Ensures we'll get no pesky warnings when zero-arity types
        # are used without parentheses (just like 'normal' types)
        if variable_refers_to_function?(variable, env) do
          {variable, meta, []}
        else
          orig
        end

      {other_fun, meta, args} when is_list(args) ->
        # Make sure arguments of any function are expanded
        {other_fun, meta, Enum.map(args, &rewrite(&1, env, options))}

      other ->
        # Fallback
        other
    end
  end

  defp variable_refers_to_function?(name, env) do
    definitions =
      env.functions
      |> Enum.flat_map(fn {_module, definitions} -> definitions end)

    {name, 0} in definitions
  end

  defp rewrite_tuple(tuple_elements, env, options) do
    rewritten_elements =
      tuple_elements
      |> Enum.map(&rewrite(&1, env, options))

    quote generated: true, location: :keep do
      TypeCheck.Builtin.fixed_tuple(unquote(rewritten_elements))
    end
  end

  defp rewrite_map_or_struct(struct_fields, orig_ast, env, options) do
    case struct_fields[:__struct__] do
      Range ->
        quote generated: true, location: :keep do
          TypeCheck.Builtin.range(unquote(orig_ast))
        end

      nil ->
        # A map with fixed fields
        # Keys are expected to be literal values
        field_types =
          Enum.map(struct_fields, fn {key, value_type} -> {key, rewrite(value_type, env, options)} end)

        quote generated: true, location: :keep do
          TypeCheck.Builtin.fixed_map(unquote(field_types))
        end

      _other ->
        # Unhandled already-expanded structs
        # Treat them as literal values
        quote generated: true, location: :keep do
          TypeCheck.Builtin.literal(unquote(orig_ast))
        end
    end
  end

  defp rewrite_struct(struct_name, fields, env, options) do
    field_types = Enum.map(fields, fn {key, value_type} -> {key, rewrite(value_type, env, options)} end)
    # TODO wrap in struct-checker
    quote generated: true, location: :keep do
      TypeCheck.Builtin.fixed_map(
        [__struct__: TypeCheck.Builtin.literal(unquote(struct_name))] ++ unquote(field_types)
      )
    end
  end
end
