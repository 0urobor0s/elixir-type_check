defmodule TypeCheck.Builtin.AnyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import TypeCheck.Builtin

  test "t() has the appropriate structure" do
    subject =  TypeCheck.Builtin.Any.t()
    assert subject.__struct__ == TypeCheck.Builtin.FixedMap
    assert subject.keypairs == [__struct__: literal(TypeCheck.Builtin.Any)]
  end
end
