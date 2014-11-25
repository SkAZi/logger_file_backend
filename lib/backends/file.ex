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


  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level, metadata: metadata} = state) do
    data = Dict.take(metadata, md)
    log_enabled = is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt and Dict.size(data) == length(md)
    
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

  defp log_event(level, msg, ts, md, %{path: path, io_device: nil} = state) when is_binary(path) do
    case open_log(level, msg, ts, md, state) do
      {:ok, io_device, inode} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device, inode: inode})
      _other ->
        {:ok, state}
    end
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: io_device, inode: inode} = state) when is_binary(path) do
    if !is_nil(inode) and inode == inode(level, msg, ts, md, state) do
      IO.write(io_device, format_event(level, msg, ts, md, state))
      {:ok, state}
    else
      log_event(level, msg, ts, md, %{state | io_device: nil, inode: nil})
    end
  end


  defp open_log(level, msg, ts, md, state = %{open_opts: opts}) do
    path = format_path(level, msg, ts, md, state)
    case (path |> Path.dirname |> File.mkdir_p) do
      :ok ->
        case File.open(path, [:append, :utf8] ++ opts) do
          {:ok, io_device} -> {:ok, io_device, inode(level, msg, ts, md, state)}
          other -> other
        end
      other -> other
    end
  end

  defp inode(level, msg, ts, md, state) do
    path = format_path(level, msg, ts, md, state)
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end


  defp format_event(level, msg, ts, md, %{format: format}) do
    Logger.Formatter.format(format, level, msg, ts, md)
  end

  defp format_path(level, msg, {{year, month, day} = date, {hour, min, sec, msec} = time}, md, %{path: path}) do
    data = Dict.merge(%{
      level: level, 
      date: Logger.Utils.format_date(date), 
      year: Logger.Utils.pad2(year),
      month: Logger.Utils.pad2(month),
      day: Logger.Utils.pad2(day),
      time: Logger.Utils.format_date(time),
      hour: Logger.Utils.pad2(hour),
      min: Logger.Utils.pad2(min),
      sec: Logger.Utils.pad2(sec),
    }, md)

    Enum.map(path, &output(&1, data))
  end

  defp output(atom, data) when is_atom(atom) do
    '#{data[atom]}'
  end
  defp output(any, _), do: any


  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level     = Keyword.get(opts, :level)
    metadata  = Keyword.get(opts, :metadata, [])
    format    = Keyword.get(opts, :format, @default_format) |> Logger.Formatter.compile
    path      = Keyword.get(opts, :path) |> Logger.Formatter.compile
    open_opts = Keyword.get(opts, :opts, [])

    %{name: name, path: path, io_device: nil, inode: nil, 
      format: format, level: level, metadata: metadata, 
      open_opts: open_opts}
  end
end
