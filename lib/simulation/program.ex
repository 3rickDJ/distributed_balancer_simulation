defmodule Simulation.Program do
  defstruct references: [0, 4, 1, 4, 2, 4, 3, 4, 2, 4, 0, 4, 1, 4, 2, 4, 3, 4],
            frames: 3,
            pages: 5,
            page_size: 1024,
            name: "Generic Program",
            from_node: Node.self()

  def new() do
    %__MODULE__{}
  end

  def new(name, references, frames, pages, page_size) do
    %__MODULE__{
      name: "#{name}:#{Node.self()}",
      from_node: Node.self(),
      references: references,
      frames: frames,
      pages: pages,
      page_size: page_size
    }
  end
end
