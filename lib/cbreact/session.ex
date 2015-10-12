require Logger
defmodule Cbreact.Session do
  use GenServer

  @pagesize 10
  def start(sensorid) do
    {:ok, pid} = Cbreact.Session.Supervisor.start_child(sensorid)
    Cbreact.Session.get_sessionid(pid)
  end

  def get_sessionid(pid) do
    GenServer.call(pid, :get_sessionid)
  end

  def set_range(pid) do
    fin   = Timex.Date.local
    start = Timex.Date.subtract(fin, {0, 86400, 0})

    set_range(pid, [Timex.DateFormat.format!(start, "{YYYY}-{0M}-{0D}T{h24}:{m}:{s}"),
                    Timex.DateFormat.format!(fin,   "{YYYY}-{0M}-{0D}T{h24}:{m}:{s}")])
  end

  def set_range(pid, [start, fin]) do
    GenServer.call(pid, {:set_range, [start, fin]})
  end

  def get_range(pid) do
    GenServer.call(pid, :get_range)
  end

  def clear_storage(state) do
    HashDict.delete(state, :processlist)
  end

  def get_process_list_page(state, pstart, rows) do
    [start, fin] = HashDict.get(state, :range)
    url = "https://#{state[:cbclientapi].hostname}:#{state[:cbclientapi].port}/api/v1/process?q=" <>
          :hackney_url.urlencode("sensor_id:#{state[:sensorid]} AND " <>
                                 "start:[* TO #{fin}] AND " <>
                                 "last_update:[#{start} TO *]") <>
                                 "&sort=start%20asc&rows=10&start=#{pstart}"
    {:ok, 200, headers, bodyref} = :hackney.get(url, [{"X-Auth-Token", state[:cbclientapi].api}], '', [ssl_options: [insecure: true]])
    {:ok, body} = :hackney.body(bodyref)
    JSX.decode!(body)

  end


  def acquire_process_count(state) do
    [start, fin] = HashDict.get(state, :range)
    url = "https://#{state[:cbclientapi].hostname}:#{state[:cbclientapi].port}/api/v1/process?q=" <>
          :hackney_url.urlencode("sensor_id:#{state[:sensorid]} AND " <>
                                 "start:[* TO #{fin}] AND " <>
                                 "last_update:[#{start} TO *]") <>
                                 "&rows=0"

    {:ok, 200, headers, bodyref} = :hackney.get(url, [{"X-Auth-Token", state[:cbclientapi].api}], '', [ssl_options: [insecure: true]])
    {:ok, body} = :hackney.body(bodyref)
    %{"total_results" => count} = JSX.decode!(body)
    webdebug(state, "Total number of in-scope processes, #{count}")

    :ets.insert(state[:sessionid], {:process_summary_count, count})
    HashDict.put(state, :process_count, count)
  end


  def acquire_process_list(state) do
    cbclientapi = HashDict.get(state, :cbclientapi)
    sensorid = HashDict.get(state, :sensorid)
    process_count = HashDict.get(state, :process_count)
    [start, fin] = HashDict.get(state, :range)
    webdebug(state, "Pagesize = #{@pagesize}")

    numpages = div(process_count, @pagesize)
    :ets.insert(state[:sessionid], {:summary_pages, (numpages+1)})

    Range.new(0, numpages)
    |> Enum.map(fn(x) -> 
    url = "https://#{state[:cbclientapi].hostname}:#{state[:cbclientapi].port}/api/v1/process?q=" <>
          :hackney_url.urlencode("sensor_id:#{state[:sensorid]} AND " <>
                                 "start:[* TO #{fin}] AND " <>
                                 "last_update:[#{start} TO *]") <>
                                 "&sort=start%20asc&rows=10&start=#{x*@pagesize}"
    {:ok, ref} = :hackney.get(url, [{"X-Auth-Token", state[:cbclientapi].api}], '', [ssl_options: [insecure: true], async: true])
    :ets.insert(state[:sessionidbag], {:summary_pages, ref})
    :ets.insert(state[:sessionidbag], {ref, {:summary_pages, x}})
    ref
    end)
#    {:page_refs, hr} = :ets.lookup(state[:sessionid], :page_refs)
#    :ets.insert(state[:sessionid], {:page_refs, HashDict.put(hr, ref, x)})   ^^ note the scope...

    state
  end

  def process_summary_page(%{"results" => results}, state) do
    Enum.reduce(results, [], fn(
    %{"id" => id,
      "segment_id" => segment_id,
      "username" => username,
      "cmdline" => cmdline,
      "childproc_count" => childproc_count,
      "crossproc_count" => crossproc_count,
      "filemod_count" => filemod_count,
      "modload_count" => modload_count,
      "netconn_count" => netconn_count,
      "regmod_count" => regmod_count}, acc) ->

    :ets.update_counter(state[:sessionid], :childproc_count,       {2, childproc_count})
    :ets.update_counter(state[:sessionid], :crossproc_count,       {2, crossproc_count})
    :ets.update_counter(state[:sessionid], :filemod_count,         {2, filemod_count})
    :ets.update_counter(state[:sessionid], :modload_count,         {2, modload_count})
    :ets.update_counter(state[:sessionid], :netconn_count,         {2, netconn_count})
    :ets.update_counter(state[:sessionid], :regmod_count,          {2, regmod_count})
    lastupdatecount = :ets.update_counter(state[:sessionid], :process_summary_count, {2, -1})
    webdebug(state, "process_summary_status_count: #{lastupdatecount}")

    [ {id, segment_id} | acc ]

    end)
  end

  def acquire_event_list(state) do
    Enum.map(state[:proclist], fn(tuple) -> Logger.debug(inspect(tuple)) end)

  end


################################################################################
#  def acquire_event_list(state) do
#    Enum.reduce(state[:proclist], [], fn(tuple, acc) -> [Task.async(fn -> get_process_events(state, tuple) end) | acc] end)
#    |> Enum.map(fn(task) -> Task.await(task, 25000) end)
#    |> inspect
#    |> Logger.debug
#
#    state
#  end
#
  def get_process_events(state, {id, segment_id}) do
    Logger.debug("Seeking #{id}/#{segment_id}")
    {:ok, pid} = Cbreact.Process.start_link({id, segment_id, state[:range], state[:sessionid]})
    GenServer.cast(pid, :pull)
  end
################################################################################

  def handle_cast(:pullsensordata, state) do
    webdebug(state, "Pulling sensordata")
    url = "https://#{state[:cbclientapi].hostname}:#{state[:cbclientapi].port}/api/v1/sensor/#{state[:sensorid]}"
    {:ok, 200, headers, bodyref} = :hackney.get(url, [{"X-Auth-Token", state[:cbclientapi].api}], '', [ssl_options: [insecure: true]])
    {:ok, body} = :hackney.body(bodyref)
    sensordata = JSX.decode!(body)
    newstate = HashDict.put(state, :sensordata, sensordata)
    :erlang.send_after(300000, self, :sensordata, [])
    req_sensor_push(self)
    {:noreply, newstate}
  end
  def handle_cast(:pull_proclist, state) do
    [start, fin] = HashDict.get(state, :range)
    webdebug(state, "Requesting count of processes: #{start} -> #{fin}")

    newstate = clear_storage(state)
    |> acquire_process_count
    |> acquire_process_list
    {:noreply, newstate}
  end

  def handle_call({:set_range,[start, fin]}, _from, state) do
#    {ok, d1} = Timex.Parse.DateTime.Parser.parse(start)
#    {ok, d2} = Timex.Parse.DateTime.Parser.parse(fin)
    GenServer.cast(self, :pull_proclist)
    newstate = HashDict.put(state, :range, [start, fin])
    {:reply, :ok, newstate}
  end

  def handle_call(:get_range, _from, state) do
    sessionid = HashDict.get(state, :range)
    {:reply, sessionid, state}
  end

  def handle_call(:get_sessionid, _from, state) do
    sessionid = HashDict.get(state, :sessionid)
    {:reply, sessionid, state}
  end

  def start_link(sensorid, sessionid) do
    GenServer.start_link(__MODULE__, {sessionid, sensorid}, name: sessionid)
  end

  def init({sessionid, sensorid}) do
    :gproc.reg({:p, :l, {:sensorid, sensorid}}, sessionid)

    :ets.new(sessionid, [:set, :protected, :named_table])
    :ets.new(set2bag(sessionid), [:bag, :protected, :named_table])
    :ets.new(set2events(sessionid), [:bag, :public, :named_table])
    :ets.insert(sessionid, {:childproc_count, 0})
    :ets.insert(sessionid, {:crossproc_count, 0})
    :ets.insert(sessionid, {:filemod_count, 0})
    :ets.insert(sessionid, {:modload_count, 0})
    :ets.insert(sessionid, {:netconn_count, 0})
    :ets.insert(sessionid, {:regmod_count, 0})

    state =
      HashDict.new
      |> HashDict.put(:sensorid, sensorid)
      |> HashDict.put(:sessionid, sessionid)
      |> HashDict.put(:sessionidbag, set2bag(sessionid))
      |> HashDict.put(:sessionidevents, set2events(sessionid))
      |> HashDict.put(:range, ["2015-01-01 00:00:00", "2015-01-01 00:00:00"])
      |> HashDict.put(:cbclientapi, struct(Cbclientapi, Application.get_env(:cbclientapi, Cbclientapi)))

#    :erlang.send_after(100, self, :pullsensordata, [])
    GenServer.cast(self, :pullsensordata)

    {:ok, state}
  end

  def handle_info(:pullsensordata, state) do
    GenServer.cast(self, :pullsensordata)
    {:noreply, state}
  end
  def handle_info({:hackney_response, ref, string}, state) when is_binary(string) do
    :ets.insert(state[:sessionidbag], {ref, string})
    {:noreply, state}
  end

  def handle_info({:hackney_response, _, {:headers, _}}, state) do
    {:noreply, state}
  end
  def handle_info({:hackney_response, _, {:status, 200, "OK"}}, state) do
    {:noreply, state}
  end
  def handle_info({:hackney_response, ref, :done}, state) do
    :ets.delete_object(state[:sessionidbag], {:summary_pages, ref})
    :ets.lookup(state[:sessionidbag], ref)
    |> Enum.reduce("", fn(x, acc) -> acc <> extractstr(x) end)
    |> JSX.decode!
    |> process_summary_page(state)
    |> Enum.map(&(get_process_events(state, &1)))

    :ets.delete(state[:sessionidbag], ref)

    {:noreply, state}
  end
  def handle_info(foo, state) do
    inspect(foo)
    |> Logger.debug
    {:noreply, state}
  end

  def extractstr({ref, {:summary_pages, _}}) do
    ""
  end

  def extractstr({ref, string}) do
    string
  end

  def get_ready_count(sessionid) do
    :gproc.lookup_values({:p, :l, sessionid}) |> Enum.count
  end
    

  def set2bag(setatom) do
    Atom.to_string(setatom) <> "bag"
    |> String.to_atom
  end
  def set2events(setatom) do
    Atom.to_string(setatom) <> "events"
    |> String.to_atom
  end

  def req_sensor_push(pid) do
    GenServer.cast(pid, :push_sensordata)
  end

  def handle_cast(:push_sensordata, state) do
    sdaatomic = state[:sensordata]
    |> Enum.map(fn({key, value}) -> {String.to_atom(key), value} end)

    str0 = struct(CbStruct.CbSensor, sdaatomic)
    str1 = %{str0 | clock_delta: String.to_integer(str0.clock_delta)}
    str2 = %{str1 | sensor_uptime: String.to_integer(str0.sensor_uptime)}
    str3 = %{str2 | uptime: String.to_integer(str0.uptime)}
    str4 = %{str3 | num_storefiles_bytes: String.to_integer(str0.num_storefiles_bytes)}
    pushstruct = %{str4 | num_eventlog_bytes: String.to_integer(str0.num_eventlog_bytes)}
    

    Cbreact.CbreactChannel.push_sensor_update(state[:sessionid], :sensorupdate, pushstruct)

    {:noreply, state}
  end

  def webdebug(state, message) do
    rendermsg = inspect(message)
    Logger.debug(rendermsg)
    Cbreact.CbreactChannel.push_sensor_update(state[:sessionid], :debuglogs, %{message: rendermsg})
    state
  end


end

defmodule CbStruct.CbSensor do
  defstruct id: 0,
    computer_name: "none",
    os_environment_display_string: "none",
    clock_delta: 0,
    uptime: 0,
    sensor_uptime: 0,
    last_update: "none",
    status: "none",
    num_eventlog_bytes: 0,
    build_version_string: "none",
    network_adapters: [],
    registration_time: "none",
    last_checkin_time: "none",
    next_checkin_time: "none",
    group_id: 0,
    num_storefiles_bytes: 0
end
            



