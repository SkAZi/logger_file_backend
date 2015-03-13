defmodule Logger.Backends.File do
  use GenEvent

  @type path      :: String.t
  @type file      :: :file.io_device
  @type inode     :: File.Stat.t
  @type format    :: String.t
  @type level     :: Logger.level
  @type metadata  :: [atom]


  @default_format "$time [$level] $message $metadata\n"

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end


  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end


  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end


  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level, metadata: metadata, tag: tag} = state) do
    data = Dict.take(md, metadata)
    log_enabled = is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt
    log_enabled = log_enabled and (tag == nil or md[:tag] == tag)

    if log_enabled do
      log_event(level, msg, ts, data, state)
    else
      {:ok, state}
    end
  end


  # helpers

  defp log_event(_level, _msg, _ts, _md, %{path: nil} = state) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{io_device: nil} = state) do
    case open_log(level, msg, ts, md, state) do
      {:ok, io_device, inode} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device, inode: inode})
      _ ->
        {:ok, state}
    end
  end

  defp log_event(level, msg, ts, md, %{io_device: io_device, inode: inode, format: format} = state) do
    if !is_nil(inode) and inode == inode(level, msg, ts, md, state) do
      IO.write(io_device, format(format, level, msg, ts, md))
      {:ok, state}
    else
      File.close(io_device)
      log_event(level, msg, ts, md, %{state | io_device: nil, inode: nil})
    end
  end

  defp open_log(level, msg, ts, md, state = %{open_opts: opts, path: path}) do
    path = format(path, level, msg, ts, md) |> List.to_string
    case (path |> Path.dirname |> File.mkdir_p) do
      :ok ->
        case File.open(path, [:append, :utf8] ++ opts) do
          {:ok, io_device} -> {:ok, io_device, inode(level, msg, ts, md, state)}
          other -> other
        end
      other -> other
    end
  end

  defp inode(level, msg, ts, md, state = %{path: path}) do
    path = format(path, level, msg, ts, md) |> List.to_string
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end


  def format(text, level, msg, {{year, month, day} = date, {hour, min, sec, msec} = time}, md) do
    data = Dict.merge(%{
      message: msg,
      level: level, 
      date: format_date(date), 
      year: pad2(year),
      month: pad2(month),
      day: pad2(day),
      time: format_time(time),
      hour: pad2(hour),
      min: pad2(min),
      sec: pad2(sec),
      metadata: Enum.map(md, fn({x, y})-> "#{x}=#{inspect y};" end)
    }, md)

    Enum.map(text, &output(&1, data))
  end

  defp format_date({y,m,d}), do: "#{y}-#{pad2(m)}-#{pad2(d)}"
  defp format_time({m,h,s,_}), do: "#{pad2(m)}:#{pad2(h)}:#{pad2(s)}"

  defp pad2(x) when x < 10, do: "0#{x}"
  defp pad2(x), do: "#{x}"

  defp output(atom, data) when is_atom(atom) do
    case data[atom] do
      nil -> ''
      val when is_binary(val) -> '#{val}'
      val -> '#{inspect val}'
    end
  end
  defp output(any, _), do: any


  def compile(str) do
    for part <- Regex.split(~r/(?<head>)\$[a-z_]+(?<tail>)/, str, on: [:head, :tail], trim: true) do
      case part do
        "$" <> code -> String.to_existing_atom(code)
        _ -> part
      end
    end
  end


  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level     = Keyword.get(opts, :level)
    metadata  = Keyword.get(opts, :metadata, [])
    format    = Keyword.get(opts, :format, @default_format) |> compile
    path      = Keyword.get(opts, :path) |> compile
    open_opts = Keyword.get(opts, :opts, [])
    tag       = Keyword.get(opts, :tag, nil)

    %{name: name, path: path, io_device: nil, inode: nil, 
      format: format, level: level, metadata: metadata, 
      open_opts: open_opts, tag: tag}
  end
end
