import Config

# Configuración dinámica basada en un archivo de texto
config_file = "config/memoria.txt"

if File.exists?(config_file) do
  {:ok, content} = File.read(config_file)
  params =
    content
    |> String.split("\n")
    |> Enum.map(fn line ->
      [key, value] = String.split(line, "=")
      {String.to_atom(key), String.trim(value)}
    end)
    |> Enum.into(%{})

  IO.puts("Configuración de memoria: #{inspect(params)}")

  config :simulation, :memoria,
    memory_size: String.to_integer(params[:memory_size]),
    virtual_size: String.to_integer(params[:virtual_size]),
    page_size: String.to_integer(params[:page_size])
else
  IO.puts("Archivo de configuración no encontrado: #{config_file}")
end
