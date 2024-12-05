defmodule Simulation.Memory do
  require Logger
  import Bitwise
  @control_bits 5
  @present 0b00001
  # @protection 0b00010
  # @modified 0b00100
  # @reference 0b01000
  # @cache_disabled 0b10000

  # def run() do
  #   run([0, 4, 1, 4, 2, 4, 3, 4, 2, 4, 0, 4, 1, 4, 2, 4, 3, 4], 3, 5, 1024)
  # end

  def run(%Simulation.Program{} = program) do
    run(program.references)
  end

  def run(reference_list) do
    memory_size = Application.get_env(:simulation, :memoria)[:memory_size]
    virtual_size = Application.get_env(:simulation, :memoria)[:virtual_size]
    page_size = Application.get_env(:simulation, :memoria)[:page_size]

    Logger.debug("Memory Size: #{memory_size}")
    Logger.debug("Virtual Size: #{virtual_size}")
    Logger.debug("Page Size: #{page_size}")

    memory = Enum.map(0..(memory_size - 1), fn _ -> -1 end)
    page_table = Enum.map(0..(virtual_size - 1), fn _ -> 0 end)

    frequency_table = Enum.map(0..(virtual_size - 1), fn _ -> 0 end)

    offset_bits = ceil(:math.log2(page_size))
    frame_bits = ceil(:math.log2(memory_size))
    page_bits = ceil(:math.log2(virtual_size))

    process_reference(
      reference_list,
      memory,
      page_table,
      frequency_table,
      offset_bits,
      frame_bits,
      page_bits
    )
  end

  defp process_reference(
         reference_list,
         memory,
         page_table,
         frequency_table,
         offset_bits,
         frame_bits,
         page_bits
       ) do
    :timer.sleep(1000)

    case reference_list do
      [] ->
        nil

      [reference | rest] ->
        {page_table, memory, frequency_table} =
          case present?(page_table, reference, frame_bits) do
            true ->
              # Incrementar frecuencia si la página ya está presente
              frequency_table = increment_frequency(frequency_table, reference)
              {page_table, memory, frequency_table}

            false ->
              {page_table, memory, frequency_table} =
                replace_page(
                  page_table,
                  reference,
                  memory,
                  frequency_table,
                  frame_bits,
                  page_bits
                )

              {page_table, memory, frequency_table}
          end

        print_log(
          reference,
          page_table,
          memory,
          frequency_table,
          @control_bits,
          frame_bits,
          page_bits,
          offset_bits,
          reference_list
        )

        process_reference(
          rest,
          memory,
          page_table,
          frequency_table,
          offset_bits,
          frame_bits,
          page_bits
        )
    end
  end

  defp replace_page(page_table, reference, memory, frequency_table, frame_bits, _page_bits) do
    case Enum.find_index(memory, fn x -> x == -1 end) do
      nil ->
        # Reemplazo por LFU: Encontrar el frame menos frecuentemente usado
        IO.puts("Reemplazo por LFU")
        {lfu_frame, _frequency} =
          memory
          |> Enum.with_index()
          |> Enum.filter(fn {page, _index} -> page != -1 end)
          |> Enum.map(fn {page, index} -> {index, Enum.at(frequency_table, page)} end)
          |> Enum.min_by(fn {_index, frequency} -> frequency end)

        lfu_page = Enum.at(memory, lfu_frame)

        memory = List.replace_at(memory, lfu_frame, reference)

        page_table =
          page_table
          |> List.replace_at(lfu_page, 0)
          |> List.replace_at(reference, lfu_frame)
          |> set_bits(reference, @present, frame_bits)

        frequency_table =
          frequency_table
          # Nueva página comienza con frecuencia 1
          |> List.replace_at(reference, 1)
          # Página reemplazada, frecuencia a 0
          |> List.replace_at(lfu_page, 0)

        {page_table, memory, frequency_table}

      memory_free_index ->
        memory = List.replace_at(memory, memory_free_index, reference)

        page_table =
          page_table
          |> set_frame_number(reference, memory_free_index)
          |> set_bits(reference, @present, frame_bits)

        # Frecuencia inicial 1
        frequency_table = List.replace_at(frequency_table, reference, 1)

        {page_table, memory, frequency_table}
    end
  end

  defp print_log(
         reference,
         page_table,
         _memory,
         frequency_table,
         control_bits,
         frame_bits,
         page_bits,
         offset_bits,
        reference_list
       ) do
    IO.puts("Reference: #{reference}:\t\t\t time remaining: #{Enum.count(reference_list)}")

    print_virtual_physical_address(
      reference,
      page_table,
      control_bits,
      frame_bits,
      page_bits,
      offset_bits
    )

    print_frame_number(page_table, reference, frame_bits)
    print_control_bits(reference, page_table, control_bits, frame_bits, page_bits)
    print_reference_count(reference, frequency_table)
    IO.puts("\n\n")
  end

  defp print_frame_number(page_table, reference, frame_bits) do
    frame_number = Enum.at(page_table, reference) |> Bitwise.band((1<<<frame_bits) - 1)
    IO.puts("\n\tFrame Number")
    IO.puts("\t\tFrame[#{reference}]: #{frame_number}")
  end

  defp print_reference_count(reference, frequency_table) do
    IO.puts("\n\tReference Count")
    IO.puts("\t\tReference[#{reference}]: #{Enum.at(frequency_table, reference)}")
  end

  defp print_control_bits(reference, page_table, control_bits, frame_bits, page_bits) do
    page_entry = Enum.at(page_table, reference)
    control_bits = page_entry |> Bitwise.bsr(frame_bits) |> Integer.to_string(2) |> String.pad_leading(control_bits, "0")
    IO.puts("\n\tControl Bits")
    IO.puts( "\t\tControl[#{reference}]: #{control_bits}")
  end

  defp print_virtual_physical_address(
         reference,
         page_table,
         control_bits,
         frame_bits,
         page_bits,
         offset_bits
       ) do
    virtual_addr = reference <<< offset_bits

    physical_addr =
      Enum.at(page_table, reference)
      |> Bitwise.band((1 <<< frame_bits) - 1)
      |> Bitwise.bsl(offset_bits)

    IO.puts(
      "\tVirtual  Address: #{virtual_addr} | 0b #{underscore_binary(virtual_addr, offset_bits)}"
    )

    IO.puts(
      "\tPhysical Address: #{physical_addr} | 0b #{underscore_binary(physical_addr, offset_bits)}"
    )
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

  defp increment_frequency(frequency_table, page_index) do
    List.update_at(frequency_table, page_index, &(&1 + 1))
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
end
