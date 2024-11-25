defmodule Simulation.Memory do
  use Bitwise
  @control_bits 5
  @present 0b00001
  @protection 0b00010
  @modified 0b00100
  @reference 0b01000
  @cache_disabled 0b10000

  def run() do
    run([0, 4, 1, 4, 2, 4, 3, 4, 2, 4, 0, 4, 1, 4, 2, 4, 3, 4], 3, 5, 1024)
  end

  def run(reference_list, memory_size, virtual_size, page_size) do
    memory = Enum.map(0..(memory_size - 1), fn _ -> -1 end)
    page_table = Enum.map(0..(virtual_size - 1), fn _ -> 0 end)
    # log base 2 of page_size
    offset_bits = ceil(:math.log2(page_size))
    frame_bits = ceil(:math.log2(memory_size))
    page_bits = ceil(:math.log2(virtual_size))
    queue = Qex.new()

    process_reference(
      reference_list,
      memory,
      page_table,
      queue,
      offset_bits,
      frame_bits,
      page_bits
    )
  end

  defp process_reference(
         reference_list,
         memory,
         page_table,
         queue,
         offset_bits,
         frame_bits,
         page_bits
       ) do
    case reference_list do
      [] ->
        nil

      [reference | rest] ->
        # if page hash bit present dont do anything
        {page_table, memory, queue} =
          case present?(page_table, reference, frame_bits) do
            true ->
              page_table = set_bits(page_table, reference, @reference, frame_bits)
              {page_table, memory, queue}

            false ->
              {page_table, memory, queue} =
                replace_page(page_table, reference, memory, queue, frame_bits, page_bits)

              {page_table, memory, queue}
          end

        print_log(reference, page_table, memory, queue, @control_bits, frame_bits, page_bits, offset_bits)
        process_reference(rest, memory, page_table, queue, offset_bits, frame_bits, page_bits)
    end
  end

  defp replace_page(page_table, reference, memory, queue, frame_bits, page_bits) do
    case Enum.find_index(memory, fn x -> x == -1 end) do
      nil ->
        {{:value, oldest_memory_frame_index}, queue} = Qex.pop(queue)
        queue = Qex.push(queue, oldest_memory_frame_index)
        old_page_index = Enum.at(memory, oldest_memory_frame_index)
        memory = List.replace_at(memory, oldest_memory_frame_index, reference)

        page_table =
          page_table
          |> List.replace_at(old_page_index, 0)
          |> List.replace_at(reference, oldest_memory_frame_index)
          |> set_bits(reference, @present, frame_bits)

        {page_table, memory, queue}

      memory_free_index ->
        queue = Qex.push(queue, memory_free_index)
        memory = List.replace_at(memory, memory_free_index, reference)

        page_table =
          page_table
          |> set_frame_number(reference, memory_free_index)
          |> set_bits(reference, @present, frame_bits)

        {page_table, memory, queue}
    end
  end

  defp print_log(reference, page_table, memory, queue, control_bits, frame_bits, page_bits, offset_bits) do
    IO.puts("\n\nReference: #{reference} | #{Integer.to_string(reference, 2)}")
    print_virtual_physical_address(reference, page_table, control_bits, frame_bits, page_bits, offset_bits)
    print_page_table(page_table, reference)
    IO.puts("\t\tQueue: #{inspect(queue)}")
    print_memory(memory)
  end

  defp print_virtual_physical_address(reference, page_table, control_bits, frame_bits, page_bits, offset_bits) do
    virtual_addr = reference <<< offset_bits
    physical_addr = Enum.at(page_table, reference) |> Bitwise.band((1 <<< frame_bits)-1) |> Bitwise.bsl(offset_bits)

    IO.puts("\tVirtual  Address: #{virtual_addr} | #{underscore_binary(virtual_addr, offset_bits)}")
    IO.puts("\tPhysical Address: #{physical_addr} | #{underscore_binary(physical_addr, offset_bits)}")
    # IO.puts("\tPhysical Address: #{physical_addr} | #{Integer.to_string(physical_addr, 2)}")
  end

  defp underscore_binary(binary, offset_bits) do
    binary
    |> Integer.to_string(2)
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(offset_bits)
    |> Enum.join("_")
    |> String.reverse()
  end


  defp print_page_table(page_table, reference) do
    IO.puts("\n\tPage Table")

    Enum.with_index(page_table, fn x, i ->
      IO.puts("\t\tPage[#{i}]: #{Integer.to_string(x, 2)} ")
    end)
  end

  defp print_memory(memory) do
    IO.puts("\n\tMemory")

    Enum.with_index(memory, fn x, i ->
      IO.puts("\t\tMemory[#{i}]: #{x} ")
    end)
  end

  defp present?(page_table, page, frame_bits) do
    Enum.at(page_table, page) |> Bitwise.bsr(frame_bits) |> Bitwise.band(@present) |> Kernel.!=(0)
  end

  defp set_frame_number(page_table, page_index, frame_number) do
    page_table
    |> List.update_at(page_index, fn x -> x ||| frame_number end)
  end

  defp set_bits(page_table, page_index, bit, frame_bits) do
    page_table
    |> List.update_at(page_index, fn x -> x ||| bit <<< frame_bits end)
  end

  defp unset_bits(page_table, page_index, bit, frame_bits) do
    page_table
    |> List.update_at(page_index, fn x -> x &&& ~~~(bit <<< frame_bits) end)
  end
end
