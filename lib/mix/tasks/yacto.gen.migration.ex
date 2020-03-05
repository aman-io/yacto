defmodule Mix.Tasks.Yacto.Gen.Migration do
  require Logger
  use Mix.Task

  @shortdoc "Generate migration file"

  @switches [prefix: :string, migration_dir: :string]

  def run(args) do
    Mix.Task.run("loadpaths", args)
    Mix.Task.run("app.start", args)

    case OptionParser.parse(args, switches: @switches) do
      {opts, [], _} ->
        app = Keyword.fetch!(Mix.Project.config(), :app)
        prefix = Keyword.get(opts, :prefix)

        migration_dir =
          Keyword.get(opts, :migration_dir, Yacto.Migration.Util.get_migration_dir_for_gen())

        _ = Application.load(app)

        {:ok, now} = DateTime.now("Etc/UTC")

        # アプリケーションにあるスキーマの一覧を手に入れる
        schemas =
          Yacto.Migration.Util.get_all_schema(app, prefix)
          |> Enum.filter(fn schema ->
            Yacto.Migration.Util.need_gen_migration?(schema)
          end)

        # 削除されてるスキーマがないかを調べるために、マイグレーション済みのスキーマ一覧を手に入れる
        {module_names, messages} = Yacto.Migration.File.list_migration_modules(migration_dir)
        for message <- messages do
          Logger.warn(message)
        end

        # operation が :delete でないマイグレーション済みスキーマとマイグレーションファイルを手に入れる
        pairs =
          module_names
          |> Enum.map(fn mod ->
            {migration_file, messages} = Yacto.Migration.File.get_latest_migration_file(migration_dir, mod)
            for message <- messages do
              Logger.warn(message)
            end
            {mod, migration_file}
          end)
          |> Enum.filter(fn {_mod, file} -> file != nil && file.operation != :delete end)

        for schema <- schemas do
          {migration_file, messages} = Yacto.Migration.File.get_latest_migration_file(migration_dir, to_string(schema.__base_schema__()))
          for message <- messages do
            Logger.warn(message)
          end

          migration =
            case migration_file do
              nil -> nil
              _ ->
                {:ok, migration} = Yacto.Migration.File.load_migration_module(migration_dir, migration_file)
                migration
            end

          result = Yacto.Migration.GenMigration.generate(
            schema,
            migration,
            Application.get_env(:yacto, :migration, [])
          )
          case result do
            # not changed
            :not_changed ->
              Logger.info("A schema #{schema} is not changed. The migration file is not generated.")
              :ok
            # generated
            {type, str, version} ->
              dbname = schema.dbname()
              operation =
                case type do
                  :created -> :create
                  :changed -> :change
                  # ここで delete は来ないはず
                  # :deleted -> :delete
                end
              migration_file = Yacto.Migration.File.new(to_string(schema.__base_schema__()), version, dbname, operation, now)

              path = Path.join(migration_dir, migration_file.path)
              File.mkdir_p!(Path.dirname(path))
              File.write!(path, str)
              Logger.info("Generated a migration file #{path} for schema #{schema}")
          end
        end

        schema_map = schemas |> Enum.map(&{to_string(&1.__base_schema__()), true}) |> Enum.into(%{})
        for {migration_schema_name, migration_file} <- pairs do
          # 削除されていない場合は何もしない
          if migration_schema_name in schema_map do
            :ok
          else
            {:ok, migration} = Yacto.Migration.File.load_migration_module(migration_dir, migration_file)

            # 削除するマイグレーションファイルを作る
            {:deleted, str, version} = Yacto.Migration.GenMigration.generate(
              nil,
              migration,
              Application.get_env(:yacto, :migration, [])
            )
            dbname = migration_file.dbname
            migration_file = Yacto.Migration.File.new(migration_schema_name, version, dbname, :delete, now)

            path = Path.join(migration_dir, migration_file.path)
            File.mkdir_p!(Path.dirname(path))
            File.write!(path, str)
            Logger.info("Generated a migration file #{path} for schema #{migration_schema_name}")
          end
        end

      {_, [_ | _], _} ->
        Mix.raise("Args error")

      {_, _, invalids} ->
        Mix.raise("Invalid arguments #{inspect(invalids)}")
    end
  end
end
