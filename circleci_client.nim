#
## Nim CircleCI API client
##
## Based on https://circleci.com/docs/api/
##
## (c) 2016 Federico Ceratto <federico.ceratto@gmail.com>
## Released under GPLv3 license, see LICENSE file
#

from cgi import encodeUrl
from strutils import strip
import httpclient
import json
import strutils

type
  CircleCIClient* = ref object of RootObj
    token, api_baseurl: string
    timeout_ms: int
    http_client: AsyncHttpClient

proc newCircleCIClient*(token: string, api_baseurl="https://circleci.com/api/v1", timeout=10000): CircleCIClient =
  new result
  result.token = token
  result.timeout_ms = timeout
  result.api_baseurl = api_baseurl
  result.http_client = newAsyncHttpClient()


type
  Headers = seq[(string, string)]
  Params = seq[(string, string)]

proc join_params(params: Params): string =
  ## Join URL query string
  result = ""
  for p in params:
    let leader = if result.len == 0: "?" else: "&"
    result.add "$#$#=$#" % [leader, p[0].encodeUrl, p[1].encodeUrl]


proc fetch(c: CircleCIClient, path: string, params: Params = @[]): JsonNode =
  let all_params = ("circle-token", c.token) & params
  let url = c.api_baseurl & path & all_params.join_params()
  let q = getContent(url, extraHeaders="Accept: application/json\c\L")
  parseJson($q)

proc post(c: CircleCIClient, path: string, data: MultipartData=nil, params: Params = @[]): JsonNode =
  let all_params = ("circle-token", c.token) & params
  let url = c.api_baseurl & path & all_params.join_params()
  echo "URL ", url
  let q = postContent(url, extraHeaders="Accept: application/json\c\L", multipart=data)
  parseJson($q)

proc user*(c: CircleCIClient): JsonNode =
  ## Fetch information about the current user
  c.fetch "/me"

proc projects*(c: CircleCIClient): JsonNode =
  ## Fetch a list of followed projects
  c.fetch "/projects"

proc recent_builds*(c: CircleCIClient, limit=30, offset=0): JsonNode =
  ## Fetch a list of recent builds across all projects
  c.fetch("/recent-builds", @[("limit", $limit), ("offset", $offset)])

proc recent_builds*(c: CircleCIClient, username, project_name: string, branch="", filter="", limit=30, offset=0): JsonNode =
  ## Fetch a list of recent builds for a projects. Optionally filter by branch and status.
  let path =
    if branch == "":
      "/project/$#/$#" % [username, project_name]
    else:
      "/project/$#/$#/tree/$#" % [username, project_name, branch.encodeUrl]

  var params: Params = @[("limit", $limit), ("offset", $offset)]
  if filter != "":
    assert filter in ["completed", "successful", "failed", "running"]
    params.add(("filter", filter))

  c.fetch(path, params)

proc build_details*(c: CircleCIClient, username, project_name: string, build_num: int): JsonNode =
  ## Fetch build details
  let path = "/project/$#/$#/$#" % [username, project_name, $build_num]
  c.fetch path

proc build_artifacts*(c: CircleCIClient, username, project_name: string, build_num: int): JsonNode =
  ## Fetch build artifacts
  let path = "/project/$#/$#/$#/artifacts" % [username, project_name, $build_num]
  c.fetch path

proc latest_build_artifacts*(c: CircleCIClient, username, project_name: string, filter="completed", branch=""): JsonNode =
  ## Fetch artifacts from the latest build. Optionally filter by branch and status
  assert filter in ["completed", "successful", "failed"]
  let path = "/project/$#/$#/latest/artifacts" % [username, project_name]
  var params: Params = @[("filter", filter)]
  if branch != "":
    params.add(("branch", branch))

  c.fetch(path, params)

proc retry_build*(c: CircleCIClient, username, project_name: string, build_num: int): JsonNode =
  ## Retry a build
  let path = "/project/$#/$#/$#/retry" % [username, project_name, $build_num]
  c.post path

proc cancel_build*(c: CircleCIClient, username, project_name: string, build_num: int): JsonNode =
  ## Cancel a build
  let path = "/project/$#/$#/$#/cancel" % [username, project_name, $build_num]
  c.post path

proc start_build*(c: CircleCIClient, username, project_name: string, revision="", tag="", branch="", parallel = -1): JsonNode =
  ## Start a build. Optionally specify "revision" or "tag".
  var data = newMultipartData()
  if revision != "":
    data["revision"] = revision
  elif tag != "":
    data["tag"] = tag
  if parallel != -1:
    data["parallel"] = $parallel
  let path =
    if branch == "":
      "/project/$#/$#" % [username, project_name]
    else:
      "/project/$#/$#/tree/$#" % [username, project_name, branch.encodeUrl]
  c.post(path, data=data)

proc clear_cache*(c: CircleCIClient, username, project_name: string): JsonNode =
  ## Clear the project cache
  let path = "/project/$#/$#/build-cache" % [username, project_name]
  c.post path

proc list_env_vars*(c: CircleCIClient, username, project_name: string): JsonNode =
  ## List env variables
  c.fetch "/project/$#/$#/envvar" % [username, project_name]

proc add_env_var(c: CircleCIClient, username, project_name, name, value: string): JsonNode =
  ## Add an env variable *BROKEN*
  var data = newMultipartData({"name": name, "value": value})
  let path = "/project/$#/$#/envvar" % [username, project_name]
  c.post(path, data)

proc fetch_env_var*(c: CircleCIClient, username, project_name, name: string): JsonNode =
  ## Fetch an env variable
  c.fetch "/project/$#/$#/envvar/$#" % [username, project_name, name]

proc list_checkout_keys*(c: CircleCIClient, username, project_name: string): JsonNode =
  ## List checkout keys
  c.fetch "/project/$#/$#/checkout-key" % [username, project_name]

proc fetch_checkout_key*(c: CircleCIClient, username, project_name, fingerprint: string): JsonNode =
  ## Fetch a checkout key
  c.fetch "/project/$#/$#/checkout-key/$#" % [username, project_name, fingerprint]

proc fetch_test_metadata*(c: CircleCIClient, username, project_name: string, build_num: int): JsonNode =
  ## Fetch an env variable
  c.fetch "/project/$#/$#/$#/tests" % [username, project_name, $build_num]





# Functional tests. A CircleCI token and a test projects are required.

when isMainModule:
  import unittest
  suite "functional tests":
    setup:
      let c = try:
        newCircleCIClient(".circleci_test_token".readFile.strip)
      except:
        echo "file .circleci_test_token not found - skipping tests"
        quit()
        nil
      let username = "FedericoCeratto"
      let project_name = "nim-ci"

    test "user":
      if false:
        let resp = c.user()
        for k in @["parallelism", "name", "projects", "sign_in_count"]:
          check resp.hasKey k

    test "recent_builds":
      if false:
        var resp = c.recent_builds(limit=1)
        check resp.len == 1

    test "recent_builds one project":
      if false:
        var resp = c.recent_builds(username, project_name, limit=1)
        check resp.len == 1

    test "recent_builds one project, single branch":
      if false:
        var resp = c.recent_builds(username, project_name, branch="master", filter="failed",limit=1)
        check resp.len == 1
        echo resp[0]["outcome"]
        echo resp[0]["build_url"]

    test "build details":
      if false:
        var resp = c.build_details(username, project_name, 147)
        for k in @["subject", "lifecycle", "outcome"]:
          check resp.hasKey k

    test "build artifacts":
      if false:
        var resp = c.build_artifacts(username, project_name, 147)
        check resp.len > 10

    test "start a build":
      if false:
        var resp = c.start_build(username, project_name)
        echo repr resp
        echo resp

    test "list env vars":
      if false:
        echo c.list_env_vars(username, project_name)

    test "create, fetch, delete env var":
      if false:
        let name = "testvar"
        let value = "test123"
        echo "adding"
        echo c.add_env_var(username, project_name, name, value)
        #FIXME
        var resp = c.fetch_env_var(username, project_name, name)
        check resp["value"].str == value

    test "list_checkout_keys then fetch_checkout_key":
      if false:
        let resp = c.list_checkout_keys(username, project_name)
        assert resp.len > 0
        let fp = resp[0]["fingerprint"].str
        let resp2 = c.fetch_checkout_key(username, project_name, fp)
        check resp[0]["public_key"].str == resp2["public_key"].str

    test "fetch test metadata":
      if false:
        echo c.fetch_test_metadata(username, project_name, 147)


