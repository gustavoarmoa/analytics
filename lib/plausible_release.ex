defmodule Plausible.Release do
  use Plausible.Repo
  require Logger

  @app :plausible
  @start_apps [
    :ssl,
    :postgrex,
    :ch,
    :ecto
  ]

  @spec selfhost? :: boolean
  def selfhost? do
    Application.fetch_env!(@app, :is_selfhost)
  end

  def should_be_first_launch? do
    selfhost?() and not (_has_users? = Repo.exists?(Plausible.Auth.User))
  end

  def migrate do
    prepare()
    Enum.each(repos(), &run_migrations_for/1)
    IO.puts("Migrations successful!")
  end

  def pending_migrations do
    prepare()
    IO.puts("Pending migrations")
    IO.puts("")
    Enum.each(repos(), &list_pending_migrations_for/1)
  end

  def seed do
    prepare()
    # Run seed script
    Enum.each(repos(), &run_seeds_for/1)
    # Signal shutdown
    IO.puts("Success!")
  end

  def createdb do
    prepare()

    for repo <- repos() do
      :ok = ensure_repo_created(repo)
    end

    IO.puts("Creation of Db successful!")
  end

  def rollback do
    prepare()

    get_step =
      IO.gets("Enter the number of steps: ")
      |> String.trim()
      |> Integer.parse()

    case get_step do
      {int, _trailing} ->
        Enum.each(repos(), fn repo -> run_rollbacks_for(repo, int) end)
        IO.puts("Rollback successful!")

      :error ->
        IO.puts("Invalid integer")
    end
  end

  def configure_ref_inspector() do
    priv_dir = Application.app_dir(:plausible, "priv/ref_inspector")
    Application.put_env(:ref_inspector, :database_path, priv_dir)
  end

  def configure_ua_inspector() do
    priv_dir = Application.app_dir(:plausible, "priv/ua_inspector")
    Application.put_env(:ua_inspector, :database_path, priv_dir)
  end

  ##############################

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp run_seeds_for(repo) do
    # Run the seed script if it exists
    seed_script = seeds_path(repo)

    if File.exists?(seed_script) do
      IO.puts("Running seed script..")
      Code.eval_file(seed_script)
    end
  end

  defp run_migrations_for(repo) do
    IO.puts("Running migrations for #{repo}")
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  defp list_pending_migrations_for(repo) do
    IO.puts("Listing pending migrations for #{repo}")
    IO.puts("")

    migration_directory = Ecto.Migrator.migrations_path(repo)

    pending =
      repo
      |> Ecto.Migrator.migrations([migration_directory])
      |> Enum.filter(fn {status, _version, _migration} -> status == :down end)

    if pending == [] do
      IO.puts("No pending migrations")
    else
      Enum.each(pending, fn {_, version, migration} ->
        IO.puts("* #{version}_#{migration}")
      end)
    end

    IO.puts("")
  end

  defp ensure_repo_created(repo) do
    IO.puts("create #{inspect(repo)} database if it doesn't exist")

    case repo.__adapter__.storage_up(repo.config) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, term} -> {:error, term}
    end
  end

  defp run_rollbacks_for(repo, step) do
    app = Keyword.get(repo.config, :otp_app)
    IO.puts("Running rollbacks for #{app} (STEP=#{step})")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, all: false, step: step))
  end

  defp prepare do
    IO.puts("Loading #{@app}..")
    # Load the code for myapp, but don't start it
    :ok = Application.load(@app)

    IO.puts("Starting dependencies..")
    # Start apps necessary for executing migrations
    Enum.each(@start_apps, &Application.ensure_all_started/1)

    # Start the Repo(s) for myapp
    IO.puts("Starting repos..")
    Enum.each(repos(), & &1.start_link(pool_size: 2))
  end

  defp seeds_path(repo), do: priv_path_for(repo, "seeds.exs")

  defp priv_path_for(repo, filename) do
    app = Keyword.get(repo.config, :otp_app)
    IO.puts("App: #{app}")
    repo_underscore = repo |> Module.split() |> List.last() |> Macro.underscore()
    Path.join([priv_dir(app), repo_underscore, filename])
  end

  defp priv_dir(app), do: "#{:code.priv_dir(app)}"
end
