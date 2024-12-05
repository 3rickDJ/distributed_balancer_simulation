defmodule Simulation.Worker do
  use GenServer
  alias Simulation.Program
  alias Simulation.Memory
  # logger
  require Logger

  # Client API
  def start_link(state) do
    # state = %{status: :free, queue: Qex.new(), program: nil, workload: 0}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(_init_arg) do
    memory_size = Application.get_env(:simulation, :memoria)[:memory_size]
    virtual_size = Application.get_env(:simulation, :memoria)[:virtual_size]
    page_size = Application.get_env(:simulation, :memoria)[:page_size]
    state = %{status: :free, queue: Qex.new(), program: nil, workload: 0, memory_size: memory_size, virtual_size: virtual_size, page_size: page_size}
    {:ok, state}
  end

  def call_nodes() do
    nodes = Node.list()
    res = GenServer.multi_call(nodes, __MODULE__, :get_state, 5000)
    Logger.debug("Responses: #{inspect(res)}")
  end

  def isFree?() do
    GenServer.call(__MODULE__, :get_state)
  end

  def change_virtual_size(virtual_size) do
    GenServer.call(__MODULE__, {:change_virtual_size, virtual_size})
  end

  def handle_call({:change_virtual_size, new_size}, _from, state) do
    Logger.debug("Changing virtual size to: #{new_size}")
    new_state = %{state | virtual_size: new_size}
    {:reply, new_state, new_state}
  end

  def force_append_work(name, references, pages) do
    program = Program.new(name, references, pages)
    Logger.debug("Forcing work: #{inspect(program)}")
    GenServer.cast(__MODULE__, {:schedule_force, program})
  end

  def append_work(name, references, pages) do
    program = Program.new(name, references, pages)
    append_work(program)
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

    Process.send_after(self(), {:check_queue}, 20)
    {:noreply, new_state}
  end

  def handle_cast({:schedule, %Program{} = program}, %{workload: workload} = state) do
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
      |> Enum.concat([{Node.self(), state}])
      |> Enum.sort(fn {k1, %{workload: workload1}}, {k2, %{workload: workload2}} ->
        if workload1 == workload2 do
          k1 >= k2
        else
          workload1 <= workload2
        end
      end)
      |> Enum.map(fn {from, %{workload: workload, virtual_size: virtual_size}} -> {from, workload, virtual_size} end)
      |> Enum.filter(fn {_from, _workload, virtual_size} ->  virtual_size >= program.pages end)
      |> Enum.map(fn {from, workload, _virtual_size} = e ->
        Logger.debug("node, workload: #{inspect(e)}")
        {from, workload}
      end)
      |> Enum.at(0)

    if nil == lazy_node do
      Logger.debug("No node found suitable for this program, skipping it.")
      {:noreply, state}
    else
      lazy_node =
        if elem(lazy_node, 1) >= workload do
          Node.self()
        else
          elem(lazy_node, 0)
        end

      Logger.debug("Lazy node: #{inspect(lazy_node)}, is the same as this node: #{inspect(Node.self() == lazy_node)}")
      GenServer.cast({__MODULE__, lazy_node}, {:schedule_force, program})
      {:noreply, state}
    end
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
            try do
              Memory.run(program)
            rescue
              e ->
                Logger.error("Error running program: #{program.name}")
                Logger.error("Error: #{inspect(e)}")
            after
              send(__MODULE__, {:task_done, program})
              %{from_node: node} = program
              if node != Node.self() do
                send({__MODULE__, node}, {:task_done, Node.self(), program})
              end
            end
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
    Logger.info("Task done for program: #{inspect(program)}")
    workload = state.workload - Enum.count(program.references)
    state = %{state | status: :free, workload: workload}
    send(__MODULE__, {:check_queue})
    {:noreply, state}
  end

  def handle_info({:task_done, from, %Program{} = program}, state) do
    Logger.info("Task done for program: #{inspect(program.name)} from: #{inspect(from)}")
    {:noreply, state}
  end
end
