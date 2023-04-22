import * as vscode from 'vscode';

import { Executable, LanguageClient, LanguageClientOptions, RevealOutputChannelOn, ServerOptions } from "vscode-languageclient/node";

let mnemeClient: LanguageClient;
let outputChannel = vscode.window.createOutputChannel("Mneme");

export function activate(context: vscode.ExtensionContext) {
	const serverOptions: Executable = {
		command: context.asAbsolutePath('./bin/mneme-language-server.exs'),
		args: [],
	};

	const clientOptions: LanguageClientOptions = {
		documentSelector: [{ scheme: "file", language: "elixir" }],
		diagnosticCollectionName: "mneme",
		revealOutputChannelOn: RevealOutputChannelOn.Never,
		progressOnInitialization: true,
		outputChannel: outputChannel,
	};

	mnemeClient = new LanguageClient(
		"mneme-vscode.ls",
		"Elixir Mneme",
		serverOptions,
		clientOptions
	);

	mnemeClient.start();
}

export function deactivate() {}
