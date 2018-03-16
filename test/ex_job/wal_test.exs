defmodule ExJob.WALTest do
  use ExUnit.Case

  alias ExJob.{WAL, Job, Queue}
  alias ExJob.WAL.Events

  @wal_path ".test_wal"
  @default_file_mod Application.get_env(:ex_job, :wal_file_mod)

  defmodule TestJob do
    use Job

    def perform(_arg), do: :ok
  end

  defmodule CustomQueueJob do
    defmodule CustomQueue do
      defstruct []

      def new do
        %__MODULE__{}
      end
    end

    defimpl ExJob.Queue, for: CustomQueueJob.CustomQueue do
      def enqueue(_, _), do: {:ok, CustomQueue.new()}
      def dequeue(_), do: {:ok, CustomQueue.new(), nil}
      def done(_, _, _), do: {:ok, CustomQueue.new()}
      def size(_, _ \\ nil), do: 0
      def working(_), do: []
    end

    use ExJob.Job

    def perform, do: :ok

    def new_queue, do: CustomQueue.new
  end

  Enum.map([WAL.File, WAL.InMemoryFile], fn file_mod ->
    describe "#{file_mod}: append/1" do
      setup do
        file_mod = unquote(file_mod)
        Application.put_env(:ex_job, :wal_file_mod, file_mod)
        on_exit fn ->
          Application.put_env(:ex_job, :wal_file_mod, @default_file_mod)
        end
        {:ok, wal} = WAL.start_link("#{@wal_path}/#{file_mod}", [])
        %{wal: wal}
      end

      test "appends events to WAL", ctx do
        event = new_event(1)
        :ok = WAL.append(ctx.wal, event)
        {:ok, events} = WAL.events(ctx.wal, TestJob)
        assert ^event = List.last(events)
      end
    end

    describe "#{file_mod}: events/1" do
      setup do
        {:ok, wal} = WAL.start_link(@wal_path, [])
        %{wal: wal}
      end

      test "starts empty", ctx do
        assert {:ok, []} = WAL.events(ctx.wal, TestJob)
      end

      test "reads WAL contents", ctx do
        event1 = new_event(1)
        event2 = new_event(2)
        event3 = new_event(3)

        assert :ok = WAL.append(ctx.wal, event1)
        assert :ok = WAL.append(ctx.wal, event2)
        assert :ok = WAL.append(ctx.wal, event3)

        {:ok, events} = WAL.events(ctx.wal, TestJob)
        assert Enum.count(events) == 4
        assert %Events.FileCreated{} = Enum.at(events, 0)
        assert Enum.at(events, 1) == event1
        assert Enum.at(events, 2) == event2
        assert Enum.at(events, 3) == event3
      end

      test "resets file pointer", ctx do
        assert {:ok, []} = WAL.events(ctx.wal, TestJob)

        event1 = new_event(1)
        :ok = WAL.append(ctx.wal, event1)
        assert {:ok, [%Events.FileCreated{}, ^event1]} = WAL.events(ctx.wal, TestJob)

        event2 = new_event(2)
        :ok = WAL.append(ctx.wal, event2)
        assert {:ok, [%Events.FileCreated{}, ^event1, ^event2]} = WAL.events(ctx.wal, TestJob)
      end
    end

    describe "#{file_mod}: read/1" do
      setup do
        {:ok, wal} = WAL.start_link(@wal_path, [])
        %{wal: wal}
      end

      test "builds an empty queue if no WAL file exists", ctx do
        {:ok, queue} = WAL.read(ctx.wal, TestJob)
        assert %ExJob.Queue.SimpleQueue{} = queue
        assert ExJob.Queue.size(queue) == 0
      end

      test "builds appropriate queue type", ctx do
        assert {:ok, %CustomQueueJob.CustomQueue{}} = WAL.read(ctx.wal, CustomQueueJob)
      end

      test "builds queue from the events in the WAL", ctx do
        job = new_job(1)

        :ok = WAL.append(ctx.wal, Events.FileCreated.new(TestJob))
        {:ok, queue} = WAL.read(ctx.wal, TestJob)
        assert Queue.size(queue) == 0

        :ok = WAL.append(ctx.wal, Events.JobEnqueued.new(job))
        {:ok, queue} = WAL.read(ctx.wal, TestJob)
        assert Queue.size(queue, :pending) == 1

        :ok = WAL.append(ctx.wal, Events.JobStarted.new(job))
        {:ok, queue} = WAL.read(ctx.wal, TestJob)
        :ok = WAL.append(ctx.wal, Events.JobDone.new(job, :success))
        assert Queue.size(queue, :working) == 0
        assert Queue.size(queue) == 0
      end
    end
  end)

  def new_event(arg), do: Events.JobEnqueued.new(new_job(arg))

  def new_job(arg), do: Job.new(TestJob, [arg])
end