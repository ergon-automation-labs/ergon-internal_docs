defmodule BotArmyInternalDocs.PulsePublisher do
  use GenServer
  require Logger

  @version Mix.Project.config()[:version]
  @publish_interval_ms 30 * 1000
  @initial_delay_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :publish_pulse, @initial_delay_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:publish_pulse, state) do
    publish_pulse()
    Process.send_after(self(), :publish_pulse, @publish_interval_ms)
    {:noreply, state}
  end

  def publish_pulse do
    payload = %{
      "bot_id" => "internal_docs",
      "status" => "alive",
      "version" => @version,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case BotArmyRuntime.NATS.Publisher.publish("bot.internal_docs.pulse", payload) do
      {:ok, _} ->
        BotArmyRuntime.SynapseHealth.publish(
          source: "bot_army_internal_docs",
          service: "internal_docs",
          health_signal: "nominal"
        )

        Logger.debug("[PulsePublisher] Pulse sent")
        :ok

      {:error, reason} ->
        Logger.warning("[PulsePublisher] Failed to send pulse: #{inspect(reason)}")
        :error
    end
  end
end
