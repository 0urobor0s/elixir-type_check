defmodule TypeCheck.Builtin.Map do
  defstruct [:key_type, :value_type]

  use TypeCheck
  @opaque! t :: %__MODULE__{key_type: TypeCheck.Type.t(), value_type: TypeCheck.Type.t()}

  @type! problem_tuple ::
         {t(), :not_a_map, %{}, any()}
         | {t(), :key_error,
            %{problem: lazy(TypeCheck.TypeError.Formatter.problem_tuple()), key: any()}, any()}
         | {t(), :value_error,
            %{problem: lazy(TypeCheck.TypeError.Formatter.problem_tuple()), key: any()}, any()}

  defimpl TypeCheck.Protocols.ToCheck do
    def to_check(s, param) do
      quote generated: true, location: :keep do
        case unquote(param) do
          x when not is_map(x) ->
            {:error, {unquote(Macro.escape(s)), :not_a_map, %{}, unquote(param)}}

          _ ->
            unquote(build_keypairs_check(s.key_type, s.value_type, param, s))
        end
      end
    end

    defp build_keypairs_check(%TypeCheck.Builtin.Any{}, %TypeCheck.Builtin.Any{}, _param, _s) do
      {:ok, []}
    end

    defp build_keypairs_check(key_type, value_type, param, s) do
      key_check =
        TypeCheck.Protocols.ToCheck.to_check(key_type, Macro.var(:single_field_key, __MODULE__))

      value_check =
        TypeCheck.Protocols.ToCheck.to_check(
          value_type,
          Macro.var(:single_field_value, __MODULE__)
        )

      quote generated: true, location: :keep do
        orig_param = unquote(param)

        orig_param
        |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, bindings} ->
          var!(single_field_key, unquote(__MODULE__)) = key
          var!(single_field_value, unquote(__MODULE__)) = value

          case {unquote(key_check), unquote(value_check)} do
            {{:ok, key_bindings}, {:ok, value_bindings}} ->
              res = {:ok, value_bindings ++ key_bindings ++ bindings}
              {:cont, res}

            {{:error, problem}, _} ->
              res =
                {:error,
                 {unquote(Macro.escape(s)), :key_error, %{problem: problem, key: key}, orig_param}}

              {:halt, res}

            {_, {:error, problem}} ->
              res =
                {:error,
                 {unquote(Macro.escape(s)), :value_error, %{problem: problem, key: key},
                  orig_param}}

              {:halt, res}
          end
        end)
      end
    end
  end

  defimpl TypeCheck.Protocols.Inspect do
    def inspect(list, opts) do
      Inspect.Algebra.container_doc(
        "map(",
        [
          TypeCheck.Protocols.Inspect.inspect(list.key_type, opts),
          TypeCheck.Protocols.Inspect.inspect(list.value_type, opts)
        ],
        ")",
        opts,
        fn x, _ -> x end,
        separator: ",",
        break: :maybe
      )
      |> Inspect.Algebra.color(:builtin_type, opts)
    end
  end

  if Code.ensure_loaded?(StreamData) do
    defimpl TypeCheck.Protocols.ToStreamData do
      def to_gen(s) do
        key_gen = TypeCheck.Protocols.ToStreamData.to_gen(s.key_type)
        value_gen = TypeCheck.Protocols.ToStreamData.to_gen(s.value_type)
        StreamData.map_of(key_gen, value_gen)
      end
    end
  end
end
