defmodule MnemeLS do
  @moduledoc """
  Mneme Language Server
  """
  use GenLSP

  alias GenLSP.Enumerations.TextDocumentSyncKind

  alias GenLSP.Notifications.Initialized

  alias GenLSP.Requests.Initialize
  alias GenLSP.Requests.Shutdown

  alias GenLSP.Structures.InitializeResult
  alias GenLSP.Structures.ServerCapabilities
  alias GenLSP.Structures.SaveOptions
  alias GenLSP.Structures.TextDocumentSyncOptions

  def start_link(_args) do
    GenLSP.start_link(__MODULE__, [], [])
  end

  @impl true
  def init(lsp, _args) do
    {:ok, lsp}
  end

  @impl true
  def handle_request(%Initialize{params: %{root_uri: root_uri}}, lsp) do
    {:reply,
     %InitializeResult{
       capabilities: %ServerCapabilities{
         text_document_sync: %TextDocumentSyncOptions{
           open_close: true,
           save: %SaveOptions{include_text: true},
           change: TextDocumentSyncKind.full()
         },
         workspace_symbol_provider: true
       },
       server_info: %{name: "MnemeLS"}
     }, assign(lsp, root_uri: root_uri)}
  end

  def handle_request(%Shutdown{}, lsp) do
    {:reply, assign(lsp, exit_code: 0)}
  end

  @impl true
  def handle_notification(%Initialized{}, lsp) do
    GenLSP.log(lsp, "[MnemeLS] Initialized")
    {:noreply, lsp}
  end
end
