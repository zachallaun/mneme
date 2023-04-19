import * as vscode from 'vscode';

import { Executable, LanguageClient, LanguageClientOptions, ServerOptions } from "vscode-languageclient/node";

let mnemeClient: LanguageClient;
let output = vscode.window.createOutputChannel("Mneme");

export function activate(context: vscode.ExtensionContext) {
	const serverOpts: Executable = {
		command: context.asAbsolutePath('./bin/mneme-language-server'),
		args: [],
	};

	const serverOptions: ServerOptions = {
		run: serverOpts,
		debug: serverOpts,
	};

	const clientOptions: LanguageClientOptions = {
		documentSelector: [{ scheme: "file", language: "elixir" }],
	};

	mnemeClient = new LanguageClient(
		"mneme-vscode.ls",
		"Elixir Mneme",
		serverOptions,
		clientOptions
	);

	mnemeClient.start().then(() => {
		console.log("Elixir Mneme: started LS");
	});
}

export function deactivate() {
	if (!mnemeClient) { return undefined; }
	return mnemeClient.stop();
}
