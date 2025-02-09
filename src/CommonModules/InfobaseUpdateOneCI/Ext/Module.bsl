﻿Procedure FillDB()
	
	// Fill Actions catalog by internal data processors
	Query = New Query;
	Query.Text = "SELECT
	|	Actions.InternalDataProcessor
	|FROM
	|	Catalog.Actions AS Actions";
	
	AlreadyAdded = Query.Execute().Unload().UnloadColumn("InternalDataProcessor");
	InternalDataProcessors = RepositoryTasks.GetInternalDataProcessors();
	For Each Item In InternalDataProcessors Do
		If AlreadyAdded.Find(Item.Value) = Undefined Then
			NewItem = Catalogs.Actions.CreateItem();
			NewItem.Description = Item.Presentation;
			NewItem.IsInternal = True;
			NewItem.InternalDataProcessor = Item.Value;
			NewItem.Write();
		EndIf; 
	EndDo; 
	
EndProcedure
 

Procedure OnStart() Export 
	Version = InfobaseUpdate.InfobaseVersion("OneCI");
	If Not ValueIsFilled(Version) Or Version = "0.0.0.0" Then
		// This is first start
		FillDB();
	EndIf; 		
EndProcedure