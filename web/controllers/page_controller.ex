defmodule Cbreact.PageController do
  use Cbreact.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
