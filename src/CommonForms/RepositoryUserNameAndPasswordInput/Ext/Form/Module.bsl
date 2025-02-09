﻿
&AtServerNoContext
Procedure SaveAtServer(Repository, UserName, Password)
	Record = InformationRegisters.RepUsers.CreateRecordManager();
	Record.Repository = Repository;
	Record.User = Tasks.GetCurrentUser(Repository);
	Record.RepUserName = UserName;
	Record.RepPassword = Password;
	Record.Write(True);
EndProcedure

&AtClient
Procedure Save(Command)
	
	If Not ValueIsFilled(UserName) Then
		UserMessage = New UserMessage();
		UserMessage.Field = "UserName";
		UserMessage.Text = "User name is not specified.";
		UserMessage.Message();
		Return; 
	EndIf; 
	
	SaveAtServer(Repository, UserName, Password);
	Params = New Structure("Task,UserName,Password",Task, UserName, Password); 
	NotifyChoice(Params);
	
EndProcedure

&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	
	Value = Undefined;
	If Parameters.Property("Task", Value) Then
		Task = Value;	
	EndIf;
	If Parameters.Property("Repository", Value) Then
		Repository = Value;	
	EndIf;
	
EndProcedure
