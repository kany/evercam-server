defmodule EvercamMedia.Snapshot.WorkerSupervisor do
  @moduledoc """
  This supervisor creates EvercamMedia.Snapshot.Worker using the strategy
  :simple_one_for_one and can only handle one child type of children.

  Since we want to dynamically create EvercamMedia.Snapshot.Worker for the cameras,
  other types of strategies in supervisor are not suitable.

  When creating a new worker, the supervisor passes on a list of @event_handlers.
  @event_handlers are the handlers that wants to react to the events generated by
  EvercamMedia.Snapshot.Worker. These handlers are automatically added to the
  event manager for every created worker.
  """

  use Supervisor
  require Logger
  alias EvercamMedia.Snapshot.StreamerSupervisor
  alias EvercamMedia.Snapshot.Worker

  @event_handlers [
    EvercamMedia.Snapshot.BroadcastHandler,
    # EvercamMedia.Snapshot.CacheHandler,
    EvercamMedia.Snapshot.DBHandler,
    EvercamMedia.Snapshot.PollHandler,
    EvercamMedia.Snapshot.StorageHandler,
    # EvercamMedia.Snapshot.StatsHandler
    # EvercamMedia.MotionDetection.ComparatorHandler
  ]

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    if Application.get_env(:evercam_media, :start_camera_workers) do
      Task.start_link(&initiate_workers/0)
    end
    children = [worker(Worker, [], restart: :permanent)]
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
  end

  @doc """
  Start camera worker
  """
  def start_worker(camera) do
    if camera do
      case get_config(camera) do
        {:ok, settings} ->
          Logger.debug "[#{settings.config.camera_exid}] Starting worker"
          Supervisor.start_child(__MODULE__, [settings])
        {:error, _message, url} ->
          Logger.warn "[#{camera.exid}] Skipping camera worker as the host is invalid: #{url}"
      end
    end
  end

  @doc """
  Reinitialize camera worker with new configuration
  """
  def update_worker(worker, camera) do
    case get_config(camera) do
      {:ok, settings} ->
        Logger.info "Updating worker for #{settings.config.camera_exid}"
        StreamerSupervisor.restart_streamer(camera.exid)
        Worker.update_config(worker, settings)
      {:error, _message} ->
        Logger.info "Skipping camera worker update as the host is invalid"
    end
  end

  @doc """
  Start a workers for each camera in the database.

  This function is intended to be called after the EvercamMedia.Snapshot.WorkerSupervisor
  is initiated.
  """
  def initiate_workers do
    Logger.info "Initiate workers for snapshot recording."
    Camera.all |> Enum.map(&(start_worker &1))
  end

  @doc """
  Given a camera, it returns a map of values required for starting a camera worker.
  """
  def get_config(camera) do
    {
      :ok,
      %{
        event_handlers: @event_handlers,
        name: camera.exid |> String.to_atom,
        config: %{
          camera_id: camera.id,
          camera_exid: camera.exid,
          vendor_exid: Camera.get_vendor_attr(camera, :exid),
          schedule: CloudRecording.schedule(camera.cloud_recordings),
          timezone: camera.timezone,
          url: Camera.snapshot_url(camera),
          auth: Camera.auth(camera),
          sleep: CloudRecording.sleep(camera.cloud_recordings),
          initial_sleep: CloudRecording.initial_sleep(camera.cloud_recordings)
        }
      }
    }
  end
end
