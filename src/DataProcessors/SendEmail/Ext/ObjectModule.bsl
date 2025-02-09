﻿// Params:
// 	LogLineNumber - serial number of event
//	CommonParams - structore with common params that exist while task running
//  Action - reference to the Action catalog element
//	ActionParams - params that was set for the action only
//  ShowMessages (bool) - determine if it needed to show interactive messages  
//
Function Run(LogLineNumber, CommonParams, Action, ActionParams, ShowMessages) Export					     
	
	Var ReturnCode;
	
	RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Start);
		
	If Not ValueIsFilled(CommonParams.DumpConfFileFullPath) Then
		RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "The saving location of configuration file is undefined", ShowMessages);
		Return False; 
	EndIf; 
		
	MessageTemplate = "";
	Recipients = Undefined;
	If ValueIsFilled(ActionParams) Then
		If Not ActionParams.Property("Recipients", Recipients) or Recipients.Count() = 0 Then
			RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "The list of message recipients is not set", ShowMessages);
			Return False;
		EndIf; 
		If Not ActionParams.Property("MessageTemplate", MessageTemplate) Then
			RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "The template of message is not set", ShowMessages);
			Return False;
		EndIf; 		
	EndIf; 
	
	If Recipients = Undefined Then
		Return True;
	EndIf; 
	
	For Each Item In CommonParams Do
		MessageTemplate = StrReplace(MessageTemplate, "[" + Item.Key + "]", String(Item.Value)); 
	EndDo; 
	MessageTemplate = StrReplace(MessageTemplate, "[CurrentDateTime]", String(CurrentDate())); 
	
	WasError = False;
	
	For Each Recipient In Recipients Do
		EmailParams = New Structure("Recipient,TextType,Body,Subject",Recipient,"PlainText", MessageTemplate, CommonParams.TaskName); 
		Try
			EmailOperations.SendEmailMessage(EmailOperations.SystemAccount(),EmailParams);			
		Except
			RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "Sending email error:" + ErrorDescription(), ShowMessages);
			WasError = true;
		EndTry; 
	EndDo; 	
	
	If Not WasError Then
		RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Success);
	EndIf; 
	
	Return Not WasError;
	
EndFunction

Function IsRepositoryDataProcessor() Export
	
	Return True; 
	
EndFunction

Function IsParamsForm() Export
	
	Return True;
	
EndFunction
