defmodule Cbreact.PageControllerTest do
  use Cbreact.ConnCase

  test "GET /" do
    conn = get conn(), "/"
    assert html_response(conn, 200) =~ "Hello Phoenix!"
  end
end
