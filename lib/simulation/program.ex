defmodule Simulation.Program do
  defstruct references: [0, 4, 1, 4, 2, 4, 3, 4, 2, 4, 0, 4, 1, 4, 2, 4, 3, 4],
            pages: 5,
            name: "Generic Program",
            from_node: Node.self()

  def new() do
    %__MODULE__{}
  end

  def new(name, references, pages) do
    %__MODULE__{
      name: "#{name}:#{Node.self()}",
      from_node: Node.self(),
      references: references,
      pages: pages,
    }
  end
end
