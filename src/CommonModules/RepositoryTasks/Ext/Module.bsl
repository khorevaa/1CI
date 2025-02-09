﻿////////////////////////////////////////////////////////////////////////////////
// Repositories subsystem
//
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//Task running

//
//
Function RunActions(LogLineNumber, Task, CommonParams, StorageAddress = Undefined, Actions = Undefined)
	
	Query = New Query;
	If Actions = Undefined  Then
		Query.Text = "SELECT
		|	TasksActions.LineNumber AS ActionNumber,
		|	TasksActions.Action,
		|	TasksActions.ActionParams,
		|	TasksActions.Action.IsInternal AS IsInternal,
		|	TasksActions.Action.InternalDataProcessor AS InternaldataProcessor,
		|	TasksActions.Action.DataProcessor AS DataProcessor
		|FROM
		|	Catalog.Tasks.Actions AS TasksActions
		|WHERE
		|	TasksActions.Ref = &Task
		|
		|ORDER BY
		|	TasksActions.LineNumber";
		Query.SetParameter("Task", Task);
		
	Else
		ActionsTable = New ValueTable();
		ActionsTable.Columns.Add("Action",New TypeDescription("CatalogRef.Actions"));
		ActionsTable.Columns.Add("ActionParams",New TypeDescription("String", ,
		New StringQualifiers(0, AllowedLength.Variable)));
		ActionsTable.Columns.Add("LineNumber",New TypeDescription("Number",
		New NumberQualifiers(6, 0, AllowedSign.Nonnegative)));
		
		For Each Item In Actions Do
			NewLine = ActionsTable.Add();
			NewLine.Action = Item.Value.Action;
			NewLine.ActionParams = Item.Value.ActionParams;
			
			NewLine.LineNumber =Item.Key;								 
		EndDo; 										
		Query = New Query;
		Query.Text = "SELECT
		|	ActionsTable.Action,
		|	ActionsTable.ActionParams,
		|	ActionsTable.LineNumber
		|INTO TT_Actions
		|FROM
		|	&ActionsTable AS ActionsTable
		|;
		|
		|////////////////////////////////////////////////////////////////////////////////
		|SELECT
		|	Actions.IsInternal,
		|	Actions.InternalDataProcessor,
		|	Actions.DataProcessor,
		|	TT_Actions.Action,
		|	TT_Actions.ActionParams,
		|	TT_Actions.LineNumber AS ActionNumber
		|FROM
		|	TT_Actions AS TT_Actions
		|		INNER JOIN Catalog.Actions AS Actions
		|		ON TT_Actions.Action = Actions.Ref
		|
		|ORDER BY
		|	ActionNumber";
		Query.SetParameter("ActionsTable", ActionsTable);
	EndIf; 
	
	ActionsSelection = Query.Execute().Select();			 
	While ActionsSelection.Next() Do
		
		If ActionsSelection.IsInternal Then
			DataProcessorName = ActionsSelection.InternaldataProcessor;
			If Not ValueIsFilled(DataProcessorName) Then
				WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, ActionsSelection.Action, Enums.ActionEventTypes.Error, "Internal data processor name is undefined", StorageAddress);
				return false;
			EndIf; 
			Try
				DataProcessor = DataProcessors[DataProcessorName].Create();
			Except
				WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, ActionsSelection.Action, Enums.ActionEventTypes.Error, "Error of getting internal data processor""" + DataProcessorName + """:" + ErrorDescription(), StorageAddress);
				return False;
			EndTry; 
			
		ElsIf Not ValueIsFilled(ActionsSelection.DataProcessor) Then
			WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, ActionsSelection.Action, Enums.ActionEventTypes.Error, "External data processor name is not specified", StorageAddress);
			return False;			
		Else   
			Try
				DataProcessor = AdditionalReportsAndDataProcessors.GetExternalDataProcessorsObject(ActionsSelection.DataProcessor);
			Except
				WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, ActionsSelection.Action, Enums.ActionEventTypes.Error, "External data processor getting error: " + ErrorDescription(), StorageAddress);			
				Return False;
			EndTry; 
			If DataProcessor = Undefined  Then
				WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, ActionsSelection.Action, Enums.ActionEventTypes.Error, "Failure of getting external data processor", StorageAddress);			
				Return False;				
			EndIf; 		
		EndIf; 
		ActionParams = Undefined;
		If ValueIsFilled(ActionsSelection.ActionParams) Then
			ActionParams = ValueFromStringInternal(ActionsSelection.ActionParams);			
		EndIf; 
		If Not DataProcessor.Run(LogLineNumber, CommonParams, ActionsSelection.Action, ActionParams, StorageAddress) Then
			return False;	
		EndIf; 
		
	EndDo; 
	
	Return True;	
	
EndFunction

Function RunScheduledTask(TaskCode) Export  
	
	Task = Catalogs.Tasks.FindByCode(TaskCode,True);
	
	If ValueIsFilled(Task) Then
		Params = New Structure("Task, ShowMessages, Repository, RepUserName, RepPassword, Actions, TaskName",Task, False); 
		RunTask(Params);
	EndIf; 
	
	
EndFunction

Function RunTaskInBackground(FormID, Task, ShowMessages = False, Repository = Undefined, RepUserName = Undefined, RepPassword = Undefined, Actions = Undefined, TaskName = Undefined) Export  
	
	Params = New Structure("Task, ShowMessages, Repository, RepUserName, RepPassword, Actions, TaskName",Task, ShowMessages, Repository, RepUserName, RepPassword, Actions, TaskName); 
	Return LongActions.ExecuteInBackground(FormID, "RepositoryTasks.RunTask", Params, "Task running");
	
EndFunction
		
// Runs all actions in the given Task
//
Function RunTask(Params, StorageAddress = Undefined) Export  
	
	LogLineNumber = 0;
	
	TaskRunningEventRef = CreateNewTaskRunningEvent(Params.Task, Params.Repository);
	
	CommonParams = New Structure("Rep, RepName, Task, TaskName, FilesystemPath, PlatformPath, DBDir, RepPath, UserName, Password, DumpConfFileFullPath, WorkingDir, ConfBackupDir,TaskRunningEventRef,TestDBDir,TestDBAdminName,TestDBAdminPassword"); 
	CommonParams.TaskRunningEventRef = TaskRunningEventRef;
	CommonParams.Rep = Params.Repository;
	CommonParams.UserName = Params.RepUserName;
	CommonParams.Password = Params.RepPassword;
		
	If Not PrepareTask(LogLineNumber, Params.Task, CommonParams, Params.Actions, Params.Repository, Params.TaskName, StorageAddress) Then
		SetTaskRunningEventState(CommonParams.TaskRunningEventRef, Enums.TaskState.Error);
		SendTaskReport(LogLineNumber, Params.Task, CommonParams, Enums.TaskState.Error, StorageAddress);
		return false;
	EndIf; 
	
	If Not RunActions(LogLineNumber, Params.Task, CommonParams, StorageAddress, Params.Actions) Then
		SetTaskRunningEventState(CommonParams.TaskRunningEventRef, Enums.TaskState.Error);
		SendTaskReport(LogLineNumber, Params.Task, CommonParams, Enums.TaskState.Error, StorageAddress);
		return false;		
	EndIf; 
	
	SetTaskRunningEventState(CommonParams.TaskRunningEventRef, Enums.TaskState.Success);
	If SendTaskReport(LogLineNumber, Params.Task, CommonParams, Enums.TaskState.Success, StorageAddress) Then
		If Params.ShowMessages Then
			Message = "The task """ + CommonParams.TaskName + """ has been successfully done!";
			PutToTempStorage(Message, StorageAddress);
		EndIf; 
		Return True;
	EndIf; 
	Return False;
	
EndFunction

// Run all actions of the task by given codes of repository and task
//
Function RunTaskByCode(RepositoryCode, TaskCode) Export
	
	Query = New Query;
	Query.Text = "SELECT
	|	Tasks.Ref AS Task
	|FROM
	|	Catalog.Tasks AS Tasks
	|WHERE
	|	Tasks.Code = &TaskCode
	|	AND Tasks.Owner.Code = &RepositoryCode";
	Query.SetParameter("RepositoryCode", RepositoryCode);
	Query.SetParameter("TaskCode", TaskCode);
	
	QueryResult = Query.Execute();
	
	If QueryResult.IsEmpty() Then
		Return False;
	EndIf; 
	
	Selection = QueryResult.Select();
	Selection.Next();
	Params = New Structure("Task, ShowMessages, Repository, RepUserName, RepPassword, Actions, TaskName",Selection.Task, False); 
	Return RunTask(Params);
	
EndFunction

//
//
Function PrepareTask(LogLineNumber, Task, CommonParams, Actions = Undefined, Repository = Undefined, TaskName = Undefined, StorageAddress = Undefined)
	
	// Get predefined action to log task operations
	TaskPrepareAction = Catalogs.Actions.PrepareTask;	
	
	WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.Start);	
	
	if Not ValueIsFilled(Task) And Actions = Undefined Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.Error, "Task is undefined", StorageAddress);	
		return false;
	EndIf;
	
	Query = New Query;
	
	If ValueIsFilled(Task)  Then
		Query.Text = "SELECT
		             |	Tasks.Owner.DBDir AS DBDir,
		             |	Tasks.Owner.PlatformPath AS PlatformPath,
		             |	Tasks.Owner.WorkingDir AS WorkingDir,
		             |	Tasks.Owner.Path AS RepPath,
		             |	Tasks.Description,
		             |	Tasks.Owner.Description AS RepName,
		             |	Tasks.Owner.ConfBackupDir AS ConfBackupDir,
		             |	Tasks.Owner AS Rep,
		             |	Tasks.Owner.TestDBDir AS TestDBDir,
		             |	Tasks.Owner.TestDBAdminName AS TestDBAdminName,
		             |	Tasks.Owner.TestDBAdminPassword AS TestDBAdminPassword
		             |FROM
		             |	Catalog.Tasks AS Tasks
		             |WHERE
		             |	Tasks.Ref = &Task";
		Query.SetParameter("Task", Task);
	Else	
		Query = New Query;
		Query.Text = "SELECT
		             |	Repositories.WorkingDir,
		             |	Repositories.PlatformPath,
		             |	Repositories.DBDir,
		             |	Repositories.ConfBackupDir,
		             |	Repositories.Path AS RepPath,
		             |	Repositories.Ref AS Rep,
		             |	Repositories.Description AS RepName,
		             |	Repositories.TestDBDir,
		             |	Repositories.TestDBAdminName,
		             |	Repositories.TestDBAdminPassword
		             |FROM
		             |	Catalog.Repositories AS Repositories
		             |WHERE
		             |	Repositories.Ref = &Repository";
		Query.SetParameter("Repository", Repository);
		
		QueryResult = Query.Execute();
		
	EndIf; 
	
	
	QueryResult = Query.Execute();
	
	TaskSelection = QueryResult.Select();
	TaskSelection.Next();
	
	CommonParams.RepPath = TaskSelection.RepPath;	
	
	CommonParams.Task = Task;
	If ValueIsFilled(TaskName) Then
		CommonParams.TaskName = TaskName;
	Else
		CommonParams.TaskName = TaskSelection.Description;	
	EndIf; 
	
	CommonParams.RepName = TaskSelection.RepName;
	CommonParams.Rep = TaskSelection.Rep;
	CommonParams.TestDBDir = TaskSelection.TestDBDir;
	CommonParams.TestDBAdminName = TaskSelection.TestDBAdminName;
	CommonParams.TestDBAdminPassword = TaskSelection.TestDBAdminPassword;
	
	If Not ValueIsFilled(CommonParams.UserName)  Then
		GetRepPasswordAndUserName(TaskSelection.Rep, CommonParams.UserName, CommonParams.Password);	
	EndIf; 
	
	If  Not ValueIsFilled(CommonParams.UserName) Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.Error, "Repository user name is undefined", StorageAddress);	
		Return False; 
	EndIf; 
	
	If Not ValueIsFilled(CommonParams.RepPath) Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.Error, "Path to repository is undefined", StorageAddress);	
		Return false;
	EndIf; 
	
	CommonParams.PlatformPath = TaskSelection.PlatformPath;
	If Not ValueIsFilled(CommonParams.PlatformPath) Then
		CommonParams.PlatformPath = BinDir() + "1cv8.exe";
	EndIf;
	
	CommonParams.WorkingDir = TaskSelection.WorkingDir;	
	If Not ValueIsFilled(CommonParams.WorkingDir) Then
		CommonParams.WorkingDir = TempFilesDir() + "\1CI_" + CommonParams.RepName + "\";
		File = New File(CommonParams.WorkingDir);
		If Not File.Exist() Then
			CreateDirectory(CommonParams.WorkingDir);	
		EndIf; 
	ElsIf Right(TrimAll(CommonParams.WorkingDir), 1) <> "\" Then
		CommonParams.WorkingDir = CommonParams.WorkingDir + "\";	
	EndIf;
	
	CommonParams.DBDir = TaskSelection.DBDir;
	
	If Not ValueIsFilled(CommonParams.DBDir) Then
		CommonParams.DBDir = CommonParams.WorkingDir + "db\";
	ElsIf Right(TrimAll(CommonParams.DBDir), 1) <> "\" Then
		CommonParams.DBDir = CommonParams.DBDir + "\";	
	EndIf; 
	
	File = New File(CommonParams.DBDir);
	If Not File.Exist() Then
		CreateDirectory(CommonParams.DBDir);	
	EndIf; 
	
	// If database folder is empty - crerate new empty db and bind it to repository
	If DirIsEmpty(CommonParams.DBDir) Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.DetailedInfo, "Configuration directory is empty (" + CommonParams.DBDir + ")", StorageAddress);	
		CreateEmptyDb(CommonParams.DBDir);
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.DetailedInfo, "The new database was created in configuration directory (" + CommonParams.DBDir + ")", StorageAddress);
		If Not BindDbToRepository(LogLineNumber, TaskPrepareAction, CommonParams, StorageAddress) Then
			Return False;
		EndIf; 
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.DetailedInfo, "The new database was binded to the repository and updated (" + CommonParams.DBDir + ")", StorageAddress);
	EndIf; 
	
	CommonParams.ConfBackupDir = TaskSelection.ConfBackupDir;
	
	If Not ValueIsFilled(CommonParams.ConfBackupDir) Then
		CommonParams.ConfBackupDir = CommonParams.WorkingDir + "Backup\";
	ElsIf Right(TrimAll(CommonParams.ConfBackupDir), 1) <> "\" Then
		CommonParams.ConfBackupDir = CommonParams.ConfBackupDir + "\";			
	EndIf; 
	
	File = New File(CommonParams.ConfBackupDir);
	If Not File.Exist() Then
		CreateDirectory(CommonParams.ConfBackupDir);	
	EndIf; 
	
	CommonParams.DumpConfFileFullPath =  CommonParams.ConfBackupDir + Format(CurrentDate(), "DF=dd.MM.yyyy") + ".cf";
	
	// The preparation of the task was successfully done
	WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, TaskPrepareAction, Enums.ActionEventTypes.Success);
	
	Return True;
	
EndFunction

//
//
Function SendTaskReport(LogLineNumber, Task, CommonParams, TaskState, StorageAddress)
	
	Query = New Query;
	Query.Text = "SELECT
	             |	TasksFailureReportRecipients.Recipient.Email AS Email,
	             |	TasksFailureReportRecipients.Recipient.ByEmail AS ByEmail,
	             |	TasksFailureReportRecipients.Recipient.TelegramUserName AS TelegramUserName,
	             |	TasksFailureReportRecipients.Recipient.ByTelegram AS ByTelegram,
	             |	TelegramUsersInfo.ChatID AS TelegramChatID
	             |FROM
	             |	Catalog.Tasks.FailureReportRecipients AS TasksFailureReportRecipients
	             |		LEFT JOIN InformationRegister.TelegramUsersInfo AS TelegramUsersInfo
	             |		ON TasksFailureReportRecipients.Recipient.TelegramUserName = TelegramUsersInfo.UserName
	             |WHERE
	             |	TasksFailureReportRecipients.Ref = &Task";
	
	If TaskState = Enums.TaskState.Success Then
		Query.Text = Query.Text + " 
		|UNION
		|
		|SELECT
		|	TasksSuccessReportRecipients.Recipient.Email,
		|	TasksSuccessReportRecipients.Recipient.ByEmail,
		|	TasksSuccessReportRecipients.Recipient.TelegramUserName,
		|	TasksSuccessReportRecipients.Recipient.ByTelegram,
		|	TelegramUsersInfo.ChatID AS TelegramChatID
		|FROM
		|	Catalog.Tasks.SuccessReportRecipients AS TasksSuccessReportRecipients
	    |		LEFT JOIN InformationRegister.TelegramUsersInfo AS TelegramUsersInfo
	    |		ON TasksSuccessReportRecipients.Recipient.TelegramUserName = TelegramUsersInfo.UserName		
		|WHERE
		|	TasksSuccessReportRecipients.Ref = &Task";	
	EndIf; 
	
	Query.SetParameter("Task", Task);
	
	Emails = New Array();
	TelegramRecipientsInfo = New ValueTable();
	TelegramRecipientsInfo.Columns.Add("TelegramUserName");
	TelegramRecipientsInfo.Columns.Add("TelegramChatID");
	
	Selection = Query.Execute().Select();
	While Selection.Next() Do
		If Selection.ByEmail Then
			Emails.Add(Selection.Email);
		EndIf; 
		If Selection.ByTelegram Then
			NewLine = TelegramRecipientsInfo.Add();
			NewLine.TelegramUserName = Selection.TelegramUserName;
			NewLine.TelegramChatID = Selection.TelegramChatID;
		EndIf; 
	EndDo; 
	
	If Emails.Count() = 0 AND TelegramRecipientsInfo.Count() = 0 Then
		return True;
	EndIf; 
	
	Query = New Query;
	Query.Text = "SELECT
	|	TaskRunningEvent.Number,
	|	TaskRunningEvent.Date,
	|	PRESENTATION(TaskRunningEvent.State) AS TaskStatePresentation
	|FROM
	|	Document.TaskRunningEvent AS TaskRunningEvent
	|WHERE
	|	TaskRunningEvent.Ref = &TaskRunningEvent
	|;
	|
	|////////////////////////////////////////////////////////////////////////////////
	|SELECT
	|	ActionEventsLog.LineNum,
	|	ActionEventsLog.Action.Description,
	|	ActionEventsLog.Description,
	|	ActionEventsLog.Date,
	|	PRESENTATION(ActionEventsLog.State) AS ActionStatePresentation
	|FROM
	|	InformationRegister.ActionEventsLog AS ActionEventsLog
	|WHERE
	|	ActionEventsLog.TaskRunningEvent = &TaskRunningEvent";
	Query.SetParameter("TaskRunningEvent", CommonParams.TaskRunningEventRef);
	
	QueryResultArray = Query.ExecuteBatch();
	
	ReportInfo = QueryResultArray[0].Select();
	ReportInfo.Next();
	
	ReportEvents = QueryResultArray[1].Select(); 
	
	Message = New TextDocument;
	
	If  Emails.Count() > 0 Then
				
		Message.AddLine("<b style='font-size:large'>The task """ + CommonParams.TaskName + """ report <i><ins>" + ReportInfo.Number + "</ins></i> from <i><ins>" + ReportInfo.Date + "</ins></i></b>");
		Message.AddLine("<p><b style='font-size:large'>Result: " + ?(TaskState = Enums.TaskState.Error, "</b><b style = 'color:red'>" + ReportInfo.TaskStatePresentation + "</b>", "<b style = 'color:green'>" + ReportInfo.TaskStatePresentation + "</b></p>"));	
		
		If ReportEvents.Count() > 0 Then
			Message.AddLine("<table border = '1' cellspacing='0' width='100%' bordercolor='#000000'><tr>");
			Message.AddLine("<th>Number</th>");
			Message.AddLine("<th>State</th>");
			Message.AddLine("<th>Name</th>");
			Message.AddLine("<th>Description</th>");
			Message.AddLine("</tr>");
			
			While ReportEvents.Next() Do
				Message.AddLine("<tr>");
				Message.AddLine("<td>" + ReportEvents.LineNum + "</td>");
				Message.AddLine("<td>" + ReportEvents.ActionStatePresentation + "</td>");
				Message.AddLine("<td>" + ReportEvents.ActionDescription + "</td>");
				Message.AddLine("<td>" + ReportEvents.Description + "</td>");
				Message.AddLine("</tr>");
			EndDo; 
			Message.AddLine("</table>");
		EndIf; 
		
	EndIf; 
	
	TelegramMessage = New TextDocument;
	
	If TelegramRecipientsInfo.Count() > 0 Then
		TelegramMessage.AddLine("The task <b>""" + CommonParams.TaskName + """</b> report <b>" + ReportInfo.Number + "</b> from <i>" + ReportInfo.Date + "</i>");
		TelegramMessage.AddLine("Result: " + ?(TaskState = Enums.TaskState.Error, "<b>" + ReportInfo.TaskStatePresentation + "</b>", "<b>" + ReportInfo.TaskStatePresentation + "</b>"));	
		
		//If ReportEvents.Count() > 0 Then
		//	Message.AddLine("<table border = '1' cellspacing='0' width='100%' bordercolor='#000000'><tr>");
		//	Message.AddLine("<th>Number</th>");
		//	Message.AddLine("<th>State</th>");
		//	Message.AddLine("<th>Name</th>");
		//	Message.AddLine("<th>Description</th>");
		//	Message.AddLine("</tr>");
		//	
		//	While ReportEvents.Next() Do
		//		Message.AddLine("<tr>");
		//		Message.AddLine("<td>" + ReportEvents.LineNum + "</td>");
		//		Message.AddLine("<td>" + ReportEvents.ActionStatePresentation + "</td>");
		//		Message.AddLine("<td>" + ReportEvents.ActionDescription + "</td>");
		//		Message.AddLine("<td>" + ReportEvents.Description + "</td>");
		//		Message.AddLine("</tr>");
		//	EndDo; 
		//	Message.AddLine("</table>");
		//EndIf; 		
	EndIf; 
	
	WasError = False;
	Action = Catalogs.Actions.SendTaskReport;
	
	// Sending emails
	For Each Recipient In Emails Do
		EmailParams = New Structure("Recipient,TextType,Body,Subject",Recipient,"HTML", Message.GetText(), "The task """ + CommonParams.TaskName + """ report "); 
		Try
			EmailOperations.SendEmailMessage(EmailOperations.SystemAccount(),EmailParams);			
		Except
			RepositoryTasks.WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "Sending email error:" + ErrorDescription(), StorageAddress);
			WasError = true;
		EndTry; 	
	EndDo; 	
	
	// Sending telegram messages
	For Each TelegramRecipientInfo In TelegramRecipientsInfo Do		
		If Not Telegram.SendTelegramMessage(LogLineNumber, Action, CommonParams, TelegramRecipientInfo.TelegramUserName, TelegramRecipientInfo.TelegramChatID, TelegramMessage.GetText(), StorageAddress) Then
			WasError = True;
		EndIf; 
	EndDo; 	
	
	Return Not WasError;
	
EndFunction

////////////////////////////////////////////////////////////////////////////////
//Repository commands operations

// Creates new empty database in the directory givrn by Dir parameter 
//
Function CreateEmptyDb(Dir) Export
	
	Try
		GetCommonTemplate("EmptyDB").Write(Dir + "1Cv8.1CD");		
	Except
		Message(ErrorDescription(), MessageStatus.Attention);
		Return false;
	EndTry; 
	
	Return True;
	
EndFunction


// Binds database to  repository
// 	Params:
// 		LogLineNumber - serial number of event
// 		Action - reference to the Action catalog element
// 		CommonParams - structore with common params that exist while task running
// 		ShowMessages (bool) - determine if it needed to show interactive messages  
//
Function BindDbToRepository(LogLineNumber, Action, CommonParams, StorageAddress) Export
	
	ReturnCode = Undefined;
	
	WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.DetailedInfo, "Try to bind database to configuration.", StorageAddress);	
	Try
		RunApp(CommonParams.PlatformPath + " DESIGNER /F """ + CommonParams.DBDir + """ /ConfigurationRepositoryF """ + CommonParams.RepPath + """ /ConfigurationRepositoryN """ + CommonParams.UserName + """ /ConfigurationRepositoryP """ + CommonParams.Password + """ /ConfigurationRepositoryBindCfg ", ,true, ReturnCode);	
	Except
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "The error of binding database to the repository:" + ErrorDescription(), StorageAddress);
		Return False; 
	EndTry; 
	
	If ReturnCode <> 0 Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "Failure of binding database to configuration: the program return " + ReturnCode, StorageAddress);	
		Return False; 
	EndIf; 
	
	WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.DetailedInfo, "Try to update database from the repository.", StorageAddress);	
	
	Try
		RunApp(CommonParams.PlatformPath + " DESIGNER /F """ + CommonParams.DBDir + """ /ConfigurationRepositoryF """ + CommonParams.RepPath + """ /ConfigurationRepositoryN """ + CommonParams.UserName + """ /ConfigurationRepositoryP """ + CommonParams.Password + """ /ConfigurationRepositoryUpdateCfg ", ,true, ReturnCode);	
	Except
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "The error of binding database to the repository:" + ErrorDescription(), StorageAddress);
		Return False; 
	EndTry; 
	
	If ReturnCode <> 0 Then
		WriteLog(LogLineNumber, CommonParams.TaskRunningEventRef, Action, Enums.ActionEventTypes.Error, "Failure of updating database from the repository: the program return " + ReturnCode, StorageAddress);	
		Return False; 
	EndIf; 
	
	Return True;
	
EndFunction


////////////////////////////////////////////////////////////////////////////////
//File system operations

// Determines if directory is empty (has no files)
// 
Function DirIsEmpty(Dir) Export
	
	Files = FindFiles(Dir, "*.*");
	return Files.Count() = 0;
	
EndFunction

// Determines if file or directory exists by given path
//
Function FileExists(Path) Export
	
	File = New File(Path);
	Return File.Exist();
	
EndFunction
 

////////////////////////////////////////////////////////////////////////////////
//Task logging

// Params:
//  Task - reference to the current task	
//
Function CreateNewTaskRunningEvent(Task, Repository = Undefined) Export
	
	NewDoc = Documents.TaskRunningEvent.CreateDocument();
	NewDoc.Task = Task;
	NewDoc.State = Enums.TaskState.Started;
	NewDoc.Date = CurrentDate();
	NewDoc.Repository = ?(Repository = Undefined, Task.Owner, Repository); // yep, there is a query to db
	NewDoc.Write();
	Return NewDoc.Ref;
	
EndFunction


// Params
// 	TaskRunningEvent - reference to existing TaskRunningEvent document
//  State - reference to the TaskState enumeration
//
Function SetTaskRunningEventState(TaskRunningEvent, State) Export 
	
	Doc = TaskRunningEvent.GetObject();
	Doc.State = State;
	Doc.Write();
	Return True;
	
EndFunction


// Params:
// 	LogLineNumber - serial number of event
// 	TaskRunningEvent - reference to existing TaskRunningEvent document
//  Action - reference to the Action catalog element
//  State - reference to the ActionEventTypes enumeration
//  Description (string type) - text description of the event
//  ShowMessages (bool) - determine if it needed to show interactive messages  
//
Function WriteLog(LogLineNumber, TaskRunningEvent, Action, State, Description = "", StorageAddress = Undefined) Export																					   
	
	RManager = InformationRegisters.ActionEventsLog.CreateRecordManager();
	Rmanager.Date = CurrentDate();
	RManager.State = State;
	RManager.TaskRunningEvent = TaskRunningEvent;
	RManager.Action = Action;
	RManager.Description = Description;
	RManager.LineNum = LogLineNumber;
	RManager.Write(True);
	LogLineNumber = LogLineNumber + 1;
	
	If StorageAddress <> Undefined Then
		PutToTempStorage(Description, StorageAddress);
	EndIf; 
	
EndFunction

////////////////////////////////////////////////////////////////////////////////
//Helpers

//
//
Function GetSystemEmailAccount() Export
	Return  Catalogs.EmailAccounts.SystemEmailAccount;		
EndFunction

//
//
Function SystemEmailAccountIsSet() Export
		
	Query = New Query;
	Query.Text = "SELECT ALLOWED
	             |	EmailAccounts.EmailAddress
	             |FROM
	             |	Catalog.EmailAccounts AS EmailAccounts
	             |WHERE
	             |	EmailAccounts.Ref = VALUE(Catalog.EmailAccounts.SystemEmailAccount)";
	
	Selection = Query.Execute().Select();
		
	If Selection.Next() Then
		
		If  ValueIsFilled(Selection.EmailAddress) Then
			Return True;  			
		EndIf; 
		
	EndIf; 
	
	Return False;
	
EndFunction

//
//
Function GetRepository(Task) Export
	Return Task.Owner;	
EndFunction

//
//
Function GetCurrentUser(Repository) Export
	
	// It seems like it is scheduled job seance
	if CurrentRunMode() = Undefined Then
		User = Repository.ScheduledJobUser;
	Else
		User = UsersClientServer.CurrentUser();	
	EndIf;
	
	Return User; 
EndFunction


// Fills given params RepUserName and RepPassword
//
Function GetRepPasswordAndUserName(Repository, RepUserName, RepPassword) Export
	
	Query = New Query;
	Query.Text = "SELECT
	|	RepUsers.RepUserName,
	|	RepUsers.RepPassword
	|FROM
	|	InformationRegister.RepUsers AS RepUsers
	|WHERE
	|	RepUsers.User = &User
	|	AND RepUsers.Repository = &Repository";
	Query.SetParameter("Repository", Repository);
	Query.SetParameter("User", GetCurrentUser(Repository));
	
	QueryResult = Query.Execute();
	If QueryResult.IsEmpty() Then
		Return False; 
	EndIf; 
	
	Selection = QueryResult.Select();
	Selection.Next();
	RepUserName = Selection.RepUserName;
	RepPassword = Selection.RepPassword;
	
	Return True;
	
EndFunction


// Gets saved action params (as value storage) 
// Params:
// Task = Task catalog ref
// ActionParamsUUID - UUID of action parameters in the actions table
//
Function LoadActionParams(Task, ActionParamsUUID) Export 
	Query = New Query;
	Query.Text = "SELECT
	|	TasksActions.ActionParams
	|FROM
	|	Catalog.Tasks.Actions AS TasksActions
	|WHERE
	|	TasksActions.Ref = &Task
	|	AND TasksActions.UUID = &ActionParamsUUID";
	Query.SetParameter("Task", Task);
	Query.SetParameter("ActionParamsUUID", ActionParamsUUID);
	
	QueryResult = Query.Execute();
	
	If QueryResult.IsEmpty() Then
		Return Undefined;
	EndIf; 
	Selection = QueryResult.Select();
	Selection.Next();
	If ValueIsFilled(Selection.ActionParams) Then
		Return   ValueFromStringInternal(Selection.ActionParams);
	EndIf; 
	Return Undefined;
	
EndFunction


// Gets string path to the data processor parameters form
// Params:
// 	Action - Actions catalog reference
//
Function GetActionsParamsFormPath(Action) Export
	
	Query = New Query;
	Query.Text = "SELECT
	|	Actions.IsInternal,
	|	Actions.InternaldataProcessor,
	|	Actions.DataProcessor
	|FROM
	|	Catalog.Actions AS Actions
	|WHERE
	|	Actions.Ref = &Action";
	Query.SetParameter("Action", Action);
	
	QueryResult = Query.Execute();
	If QueryResult.IsEmpty() Then
		Message("The action was not found by given reference", MessageStatus.Ordinary); 
		Return Undefined; 
	EndIf;  	
	
	ActionsSelection = QueryResult.Select();
	If ActionsSelection.Next() Then		
		If ActionsSelection.IsInternal Then
			Return "DataProcessor." + ActionsSelection.InternaldataProcessor + ".Form.ParamsForm";
			
		ElsIf Not ValueIsFilled(ActionsSelection.DataProcessor) Then
			Message("External data processor is not specified", MessageStatus.Ordinary); 
			return Undefined;			
		Else   
			Try
				DataProcessor = AdditionalReportsAndDataProcessors.GetExternalDataProcessorsObject(ActionsSelection.DataProcessor);
			Except
				Message("External data processor getting error: " + ErrorDescription(), MessageStatus.Attention);
				Return Undefined;
			EndTry; 
			If DataProcessor = Undefined  Then
				Message("Failure of getting external data processor", MessageStatus.Attention);
				Return Undefined;				
			EndIf; 
			Return "ExternalDataProcessor." + DataProcessor.Metadata().Name + ".Form.ParamsForm";
			
		EndIf; 
		
	EndIf; 
	
	Return Undefined;
	
EndFunction


// Determines if the Action data processor has a params form
// Params:
// 	Action - Actions catalog reference
//
Function ActionDataProcessorHasSettings(Action) Export  
	
	Query = New Query;
	Query.Text = "SELECT
	|	Actions.IsInternal,
	|	Actions.InternaldataProcessor,
	|	Actions.DataProcessor
	|FROM
	|	Catalog.Actions AS Actions
	|WHERE
	|	Actions.Ref = &Action";
	Query.SetParameter("Action", Action);
	
	QueryResult = Query.Execute();
	If QueryResult.IsEmpty() Then
		Return False; 
	EndIf;  	
	
	ActionsSelection = QueryResult.Select();
	If ActionsSelection.Next() Then
		
		If ActionsSelection.IsInternal Then
			DataProcessorName = ActionsSelection.InternaldataProcessor;
			If Not ValueIsFilled(DataProcessorName) Then
				Message("Internal data processor name is undefined", MessageStatus.Ordinary); 
				return false;
			EndIf; 
			Try
				DataProcessor = DataProcessors[DataProcessorName].Create();
			Except
				Message(ErrorDescription(), MessageStatus.Attention);
				return False;
			EndTry; 
			
		ElsIf Not ValueIsFilled(ActionsSelection.DataProcessor) Then
			Message("External data processor name is not specified", MessageStatus.Ordinary); 
			return False;			
		Else   
			Try
				DataProcessor = AdditionalReportsAndDataProcessors.GetExternalDataProcessorsObject(ActionsSelection.DataProcessor);
			Except
				Message("External data processor getting error: " + ErrorDescription(), MessageStatus.Attention);
				Return False;
			EndTry; 
			If DataProcessor = Undefined  Then
				Message("Failure of getting external data processor", MessageStatus.Attention);
				Return False;				
			EndIf; 
		EndIf; 
		
		Try
			Return DataProcessor.IsParamsForm();
		Except
			Return False;
		EndTry; 		
	EndIf; 
	
	Return False;
	
EndFunction
 
//
//
Function GetInternalDataProcessors() Export 
	DataProcessorsList = New ValueList;
	For Each Item In Metadata.DataProcessors Do
		obj = DataProcessors[Item.Name].Create();
		IsRepositoryDataProcessor = False;
		Try
			IsRepositoryDataProcessor = obj.IsRepositoryDataProcessor();	
		Except
		EndTry; 
		If IsRepositoryDataProcessor Then
			DataProcessorsList.Add(Item.Name, Item.Synonym);	
		EndIf; 
	EndDo; 		
	Return DataProcessorsList;
EndFunction
