defmodule Simulation.Worker do
  use GenServer
  alias Simulation.Program
  alias Simulation.Memory
  # logger
  require Logger

  # Client API
  def start_link(_initial_state) do
    state = %{status: :free, queue: Qex.new(), program: nil, workload: 0}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def call_nodes() do
    nodes = Node.list()
    res = GenServer.multi_call(nodes, __MODULE__, :get_state, 5000)
    Logger.debug("Responses: #{inspect(res)}")
  end

  def isFree?() do
    GenServer.call(__MODULE__, :get_state)
  end

  def append_work(name, references, frames, pages, page_size) do
    program = Program.new(name, references, frames, pages, page_size)
    append_work(program)
  end

  def force_append_work(name, references, frames, pages, page_size) do
    program = Program.new(name, references, frames, pages, page_size)
    Logger.debug("Forcing work: #{inspect(program)}")
    GenServer.cast(__MODULE__, {:schedule_force, program})
  end

  defp append_work(%Program{} = program) do
    Logger.debug("Appending work: #{inspect(program)}")
    GenServer.cast(__MODULE__, {:schedule, program})
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:schedule_force, %Program{} = program}, state) do
    Logger.debug("Scheduling in #{Node.self()} program:  #{inspect(program)}")
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

  def handle_cast({:schedule, %Program{} = program}, state) do
    Logger.debug("Scheduling program: #{inspect(program)}")
    nodes = Node.list()
    Logger.debug("Checking for lazy node on these #{inspect(nodes)}")

    {success, failure} =
      GenServer.multi_call(nodes, __MODULE__, :get_state, 5000)

    if [] != failure do
      Logger.error("Multicall failure on these nodes: #{inspect(failure)}")
    end

    lazy_node =
      success
      |> Enum.concat([{Node.self, state}])
      |> Enum.sort_by(fn {_, %{workload: workload}} -> workload end)
      |> Enum.map(fn e ->
        Logger.debug("Node: #{inspect(e)}")
        e
      end)
      |> Enum.map(fn {from, %{workload: workload}} -> {from, workload} end)
      |> Enum.map(fn e ->
        Logger.debug("node, workload: #{inspect(e)}")
        e
      end)
      |> Enum.at(0)
      |> Kernel.elem(0)

    Logger.debug("Lazy node: #{inspect(lazy_node)}")
    Logger.debug("Lazy node is the same one: #{inspect(Node.self() == lazy_node)}")

    GenServer.cast({__MODULE__, lazy_node}, {:schedule_force, program})
    {:noreply, state}
  end

  def handle_info({:check_queue}, state) do
    if state.status == :busy do
      Logger.info("Worker busy: Waiting for task to complete")
      {:noreply, state}
    else
      Logger.info("Checking queue for work")

      case Qex.pop(state.queue) do
        {{:value, program}, q} ->
          Logger.info("Starting program: #{inspect(program)}")
          new_state = %{state | status: :busy, program: program.name, queue: q}

          spawn(fn ->
            Memory.run(program)
            send(__MODULE__, {:task_done, program})
          end)

          {:noreply, new_state}

        {:empty, _q} ->
          Logger.info("Queue is empty: No work")
          new_state = %{state | status: :free}
          {:noreply, new_state}
      end
    end
  end

  def handle_info({:task_done, %Program{} = program}, state) do
    IO.puts("Task done for program: #{inspect(program)}")
    Logger.info("Task done for program: #{program.name}")
    workload = state.workload - Enum.count(program.references)
    state = %{state | status: :free, workload: workload}
    send(__MODULE__, {:check_queue})
    {:noreply, state}
  end
end
