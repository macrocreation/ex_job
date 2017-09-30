defmodule ExJob do
  @moduledoc """
  Documentation for ExJob.
  """

  alias ExJob.QueueManager

  @doc """
  Enqueues a job that will be processed by **job_module** with **args**
  passed to it.
  """
  def enqueue(job_module, args \\ [])
  def enqueue(job_module, args) when is_list(args) do
    job = ExJob.Job.new(job_module, args)
    :ok = QueueManager.enqueue(job)
    :ok = job.dispatcher.dispatch(QueueManager, job.queue_name)
    :ok
  end
  def enqueue(job_module, args) do
    error = "expected list, got ExJob.enqueue(#{inspect(job_module)}, #{inspect(args)})"
    raise(ArgumentError, error)
  end

  @doc """
  Returns information on jobs, workers and queues.
  """
  def info do
    QueueManager.info()
  end
end