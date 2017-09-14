defmodule RexTest do
  use ExUnit.Case, async: true
  doctest Rex

  defmodule TestJob do
    def perform(test_id) do
      send(test_id, :test_job_ack)
    end
  end

  test "processes a job" do
    {:ok, _} = Rex.QueueManager.Supervisor.start_link
    :ok = Rex.enqueue(TestJob, [self()])
    assert_receive :test_job_ack
  end
end
