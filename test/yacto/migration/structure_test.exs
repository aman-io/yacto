defmodule Yacto.Migration.StructureTest do
  use PowerAssert

  defmodule Schema do
    use Yacto.Schema

    def dbname() do
      :default
    end

    schema @auto_source do
    end
  end

  defmodule Test do
    defstruct []
  end

  test "inspect" do
    structure = Yacto.Migration.Structure.from_schema(Schema)

    assert "%Yacto.Migration.Structure{primary_key: [:id], source: \"yacto_migration_structuretest_schema\"}" ==
             inspect(structure)

    assert "%Yacto.Migration.Structure{primary_key: [:id], source: \"yacto_migration_structuretest_schema\"}" ==
             Yacto.Migration.Structure.to_string(structure)
  end
end
