defmodule BotArmyInternalDocs.Application do
  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_repo()
      |> maybe_add_stores()
      |> maybe_add_pulse()
      |> maybe_add_consumer()
      |> Enum.reverse()

    opts = [strategy: :one_for_one, name: BotArmyInternalDocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyInternalDocs.Repo | children]
  end

  defp maybe_add_stores(children) do
    if @env == :test do
      children
    else
      [
        {BotArmyInternalDocs.Stores.DocSourceStore, []},
        {BotArmyInternalDocs.Stores.DocChunkStore, []}
        | children
      ]
    end
  end

  defp maybe_add_pulse(children) do
    if @env == :test, do: children, else: [{BotArmyInternalDocs.PulsePublisher, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyInternalDocs.NATS.Consumer, []} | children]
  end
end
