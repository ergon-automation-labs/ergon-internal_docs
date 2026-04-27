defmodule BotArmyInternalDocs.PulsePublisher do
  @moduledoc """
  Publishes heartbeat pulses to NATS for liveness monitoring.
  """

  require Logger

  def publish_pulse do
    payload = %{
      "bot_id" => "internal_docs",
      "status" => "alive",
      "version" => Mix.Project.config()[:version],
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case BotArmyRuntime.NATS.Publisher.publish("bot.internal_docs.pulse", payload) do
      {:ok, _} ->
        Logger.debug("[PulsePublisher] Pulse sent")
        :ok

      {:error, reason} ->
        Logger.warning("[PulsePublisher] Failed to send pulse: #{inspect(reason)}")
        :error
    end
  end
end
