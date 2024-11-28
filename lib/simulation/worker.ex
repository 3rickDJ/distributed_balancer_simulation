defmodule Simulation.Worker do
  use GenServer
  alias Simulation.Program
  alias Simulation.Memory
  #logger
  require Logger

  # Client API
  def start_link(_initial_state) do
    state = %{status: :free, queue: Qex.new(), program: nil, workload: 0}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def call_nodes() do
    nodes = Node.list()
    res = GenServer.multi_call(nodes, __MODULE__, :isFree?, [])
    Logger.info("Responses: #{inspect(res)}")

  end

  def isFree?() do
    :timer.sleep(4000)
    GenServer.call(__MODULE__, :get_state)
  end

  def append_work(program) do
    GenServer.cast(__MODULE__, {:schedule, program})
  end

  # Server Callbacks
  # def init(_initial_state) do
  #   state = %{status: :free, queue: Qex.new(), program: nil}
  #   {:ok, state}
  # end

  def handle_call(:get_state, _from, state) do
    :timer.sleep(3000)
    {:reply, state, state}
  end

  def handle_cast({:schedule, %Program{} = program}, state) do
    IO.puts("Scheduling program: #{inspect(program)}")
    workload = state.workload + Enum.count(program.references)

    new_state = %{
      state
      | program: program.name,
        queue: Qex.push(state.queue, program),
        workload: workload
    }

    Process.send_after(self(), {:check_queue}, 0)
    {:noreply, new_state}
  end

  def handle_info({:check_queue}, state) do
    if state.status == :busy do
      IO.puts("Worker busy: Waiting for task to complete")
      {:noreply, state}
    else
      IO.puts("Worker free: Checking queue for work")
      nodes = Node.list()
      {success, fail} = :erpc.multicall(
        nodes,
        __MODULE__,
        :isFree?,
        []
      )

      IO.puts("Responses: #{inspect(success)}")
      IO.puts("Responses: #{inspect(fail)}")

      case Qex.pop(state.queue) do
        {{:value, program}, q} ->
          IO.puts("Starting program: #{inspect(program)}")
          new_state = %{state | status: :busy, program: program.name, queue: q}

          spawn(fn ->
            Memory.run(program)
            send(__MODULE__, {:task_done, program})
          end)

          {:noreply, new_state}

        {:empty, _q} ->
          IO.puts("Queue is empty: No work")
          new_state = %{state | status: :free}
          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_done, %Program{} = program}, state) do
    IO.puts("Task done for program: #{inspect(program)}")
    workload = state.workload - Enum.count(program.references)
    state = %{state | status: :free, workload: workload}
    send(__MODULE__, {:check_queue})
    {:noreply, state}
  end

  def handle_cast(:exit, state) do
    exit(:normal)
    {:noreply, state}
  end
end
