defmodule FindependenceHosted.CommonPassphrases do
  @moduledoc """
  The most commonly used passphrases of at least 12 characters, which sign-up and passphrase changes refuse
  (REQ-197 AC-2, WI-085; ASSESS-002 FND-202). Shorter ones are refused by length already.

  `priv/common_passphrases.txt` is built from two lists in SecLists (MIT licence),
  Passwords/Common-Credentials: `100k-most-used-passwords-NCSC.txt` (the UK National Cyber Security Centre's
  list from Have I Been Pwned, sha256 c2e56968…c576e0) and `Pwdb_top-1000000.txt` (sha256 e9a88f67…a18c9fc8),
  fetched 2026-10-01: entries of 12 to 200 printable ASCII characters, lowercased, sorted, unique (30,371).
  Its own sha256 is pinned by a test. A passphrase is compared trimmed and lowercased.
  """

  @path Path.join([__DIR__, "..", "..", "priv", "common_passphrases.txt"])
  @external_resource @path

  @list @path |> File.read!() |> String.split("\n", trim: true) |> MapSet.new()

  @doc "Whether this passphrase is one of the most commonly used."
  def common?(pass) when is_binary(pass),
    do: MapSet.member?(@list, pass |> String.trim() |> String.downcase())

  def common?(_), do: false

  @doc "How many entries the list holds."
  def size, do: MapSet.size(@list)
end
