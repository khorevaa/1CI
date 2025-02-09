﻿&AtClient 
Var LongActioinForm;

&AtClient
Var IdleHandlerParams;

&AtServer
Procedure SetAvailability()
	
	// Set editing availability
	Items.Tasks.ChangeRowSet = Not Repository.IsEmpty();
	Items.RunTaskButton.Enabled = (Items.Tasks.CurrentRow <> Undefined);
	
EndProcedure
 

&AtServer 
Procedure SetTaskFilter()	
	Tasks.Filter.Items.Clear();
	Item = Tasks.Filter.Items.Add(Type("DataCompositionFilterItem"));
	Item.LeftValue = New DataCompositionField("Owner");
	Item.ComparisonType = DataCompositionComparisonType.Equal;
	Item.Use = true;
	Item.RightValue = Repository;	
	SetAvailability();		
EndProcedure

&AtClient
Procedure RepositoryOnChange(Item)
	SetTaskFilter();
EndProcedure

&AtServer
Procedure OnCreateAtServer(Cancel, StandardProcessing)
	Settings = CommonUse.CommonSettingsStorageLoad("StartPage","StartPage");
	
	If ValueIsFilled(Settings) Then
		Value = Undefined;
		If Settings.Property("Repository", Value) Then
			Repository = Value;	
		EndIf; 		
	EndIf; 	
	
	SetTaskFilter();

EndProcedure

&AtClient
Procedure OnClose()
	OnCloseAtServer();
EndProcedure

&AtServer
Procedure OnCloseAtServer()
	
	Settings = New Structure("Repository", Repository); 
	CommonUse.CommonSettingsStorageSave("StartPage","StartPage", Settings);
	
EndProcedure

&AtServerNoContext
Function JobCompleted(JobID)
	Return LongActions.JobCompleted(JobID);	
EndFunction
 
&AtServer
Procedure LoadResult()	
	Result = GetFromTempStorage(StorageAddress);
	If TypeOf(Result) = Type("String") And ValueIsFilled(Result) Then
		CommonUseClientServer.MessageToUser(Result);	
	EndIf; 			
EndProcedure
  
&AtClient
Procedure CheckJobFinishing() Export 
	
	Try
		If LongActioinForm.IsOpen() 
			And LongActioinForm.JobID = JobID Then
			If JobCompleted(JobID) Then 
				LongActionsClient.CloseLongActionForm(LongActioinForm);				
				LoadResult();
			Else
				LongActionsClient.UpdateIdleHandlerParameters(IdleHandlerParams);
				AttachIdleHandler("CheckJobFinishing", IdleHandlerParams.CurrentInterval, True);
			EndIf;
		EndIf;
	Except
		LongActionsClient.CloseLongActionForm(LongActioinForm);
		Raise;
	EndTry;	
	
EndProcedure

&AtClient
Procedure RunTaskInBackground(Task, RepUserName, RepPassword)
	JobStruct = RepositoryTasks.RunTaskInBackground(ThisForm.UUID, Task, True, Repository, RepUserName, RepPassword);
	JobID = JobStruct.JobID;
	StorageAddress = JobStruct.StorageAddress;
	LongActioinForm = LongActionsClient.OpenLongActionForm(ThisForm, JobStruct.JobID);
	LongActionsClient.InitIdleHandlerParameters(IdleHandlerParams);
	AttachIdleHandler("CheckJobFinishing", IdleHandlerParams.CurrentInterval, True);
EndProcedure
 
&AtClient
Procedure RunTask(Command)
		
	CurData = Items.Tasks.CurrentData;
	If CurData <> Undefined Then
		RepUserName = Undefined;
		RepPassword = Undefined;
		
		RepositoryTasks.GetRepPasswordAndUserName(Repository, RepUserName, RepPassword);	
		If ValueIsFilled(RepUserName) Then
			RunTaskInBackground(CurData.Ref, RepUserName, RepPassword);
		Else
			Params = New Structure("Repository, Task", Repository, CurData.Ref);
			OpenForm("CommonForm.RepositoryUserNameAndPasswordInput", Params, ThisForm, , WindowOpenVariant.SingleWindow);
		EndIf; 
	EndIf; 		
	
EndProcedure


&AtClient
Procedure TasksOnActivateRow(Item)
	Items.RunTaskButton.Enabled = (Items.Tasks.CurrentData <> Undefined);	
EndProcedure


&AtClient
Procedure ChoiceProcessing(SelectedValue, ChoiceSource)
	If TypeOf(SelectedValue) = Type("Structure") Then
		UserName = Undefined;
		Password = Undefined;
		Task = Undefined;
		SelectedValue.Property("Task", Task);
		SelectedValue.Property("UserName", UserName);
		SelectedValue.Property("Password", Password);	
		RunTaskInBackground(Task, UserName, Password);
	EndIf; 
EndProcedure

