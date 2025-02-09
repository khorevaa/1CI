﻿// StandardSubsystems.BaseFunctionality

// ValueList for accumulating a message package generated in the client business logic 
// for the event log.
Var MessagesForEventLog Export; 
// Flag that shows whether the file system installation must be suggested in the current session.
Var SuggestFileSystemExtensionInstallation Export;
// Flag that shows whether the standard exit confirmation required in the current session.
Var SkipExitConfirmation Export;
// Parameter structure used when starting and exiting the application.
Var ParametersOnApplicationStartAndExit Export;
// Form closure confirmation parameter structure.
Var FormClosingConfirmationParameters Export;
// External resource request confirmation notification.
Var NotificationOnExternalResourceRequestApply Export;

// End StandardSubsystems.BaseFunctionality

Procedure BeforeStart()
	
	// StandardSubsystems
	StandardSubsystemsClient.BeforeStart();
	// End StandardSubsystems
	
EndProcedure

Procedure OnStart()
	
	// CI >
	If Left(LaunchParameter, 4) = "run_" Then		
		Try
			Execute(Mid(LaunchParameter,5));
		Except
			Message("Executing code failure: " + ErrorDescription(), MessageStatus.Ordinary); 
		EndTry; 
		Exit(False, False, );
	EndIf; 	
	InfobaseUpdateOneCI.OnStart();	
	// CI <
	
	// StandardSubsystems
	StandardSubsystemsClient.OnStart();
	// End StandardSubsystems	
	
EndProcedure

Procedure BeforeExit(Cancel)
	
	// StandardSubsystems
	StandardSubsystemsClient.BeforeExit(Cancel);
	// End StandardSubsystems
	
EndProcedure