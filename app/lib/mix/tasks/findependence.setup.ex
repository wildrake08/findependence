defmodule Mix.Tasks.Findependence.Setup do
  @shortdoc "Create a household vault; each member types their own passphrase"
  @moduledoc """
    mix findependence.setup PATH NAME [NAME ...]

  Creates an encrypted vault at PATH. Each named member is asked for a passphrase in turn.
  Hand the keyboard to each person privately (ASM-022); passphrases are not echoed.
  """
  use Mix.Task

  @impl true
  def run([path | names]) when names != [] do
    if File.exists?(path), do: Mix.raise("#{path} already exists")
    Mix.shell().info(FindependenceApp.Web.release_notice())

    pairs =
      Enum.map(names, fn name ->
        Mix.shell().info(
          "\n#{name}: please type your passphrase privately (at least 12 characters)."
        )

        {name, prompt_twice(name)}
      end)

    FindependenceApp.Vault.write!(FindependenceApp.Vault.create(pairs), path)
    Mix.shell().info("\nCreated #{path} for #{Enum.join(names, ", ")}.")
  end

  def run(_), do: Mix.raise("usage: mix findependence.setup PATH NAME [NAME ...]")

  defp secret!(prompt) do
    case FindependenceApp.Secret.read(prompt) do
      {:ok, text} ->
        text

      {:error, :no_input} ->
        Mix.raise("No passphrase was entered. Setup stopped; nothing was created.")
    end
  end

  defp prompt_twice(name) do
    a = secret!("Passphrase: ")
    b = secret!("Again, to confirm: ")

    cond do
      a != b -> Mix.shell().info("They did not match. Try again.") && prompt_twice(name)
      String.length(a) < 12 -> Mix.shell().info("Too short. Try again.") && prompt_twice(name)
      true -> a
    end
  end
end
