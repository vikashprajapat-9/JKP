@isTest
private class ProjectConfigurationControllerTest {

    private static final String FILE_URL = 'https://utillabs-my.sharepoint.com/:b:/g/personal/test/price-sheet';

    @testSetup
    static void setup() {
        // Both projects already have their own OneDrive folder, which configuration folders need
        Project__c skyline = new Project__c(Name = 'Skyline Towers', Active__c = true, Document_Id__c = 'SKYLINE-ROOT');
        Project__c harbour = new Project__c(Name = 'Harbour View', Active__c = true, Document_Id__c = 'HARBOUR-ROOT');
        insert new List<Project__c>{ skyline, harbour };

        insert new List<Document__c>{
            new Document__c(Name = 'Project Configurations', Project__c = skyline.Id, Document_Id__c = 'SKYLINE-CONFIGURATIONS'),
            new Document__c(Name = 'Marketing', Project__c = harbour.Id, Document_Id__c = 'HARBOUR-MARKETING')
        };
        Document__c harbourMarketing = [SELECT Id FROM Document__c WHERE Document_Id__c = 'HARBOUR-MARKETING' WITH SYSTEM_MODE];
        insert new Sub_Document__c(Name = 'harbour-brochure.pdf', Document__c = harbourMarketing.Id, File_URL__c = FILE_URL);
    }

    private static Id projectId(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    // The configuration's folder Document (added by the trigger), marked as created in OneDrive
    private static Document__c readyFolder(Id configurationId) {
        Document__c folder = [SELECT Id, Name FROM Document__c WHERE Project_Configuration__c = :configurationId WITH SYSTEM_MODE LIMIT 1];
        folder.Document_Id__c = 'FOLDER-' + configurationId;
        update folder;
        return folder;
    }

    private static Id uploadInto(Document__c folder, String fileName) {
        Sub_Document__c file = new Sub_Document__c(Name = fileName, Document__c = folder.Id, File_URL__c = FILE_URL);
        insert file;
        return file.Id;
    }

    private static ProjectConfigurationController.ConfigurationInput row(String unitType, Decimal price, Decimal squareFt) {
        ProjectConfigurationController.ConfigurationInput input = new ProjectConfigurationController.ConfigurationInput();
        input.unitType = unitType;
        input.startingPrice = price;
        input.squareFt = squareFt;
        return input;
    }

    private static List<ProjectConfigurationController.ConfigurationInput> rows(ProjectConfigurationController.ConfigurationInput input) {
        return new List<ProjectConfigurationController.ConfigurationInput>{ input };
    }

    // Returns the error shown to the user, or null when the rows were saved
    private static String createError(Id projectId, List<ProjectConfigurationController.ConfigurationInput> inputs) {
        try {
            ProjectConfigurationController.createConfigurations(projectId, inputs);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void loadsConfigurationsInUnitTypeOrderWithTheirFoldersAndFiles() {
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c threeBr = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR', Starting_Price__c = 16400000, Square_FT__c = 1560);
        Project_Configuration__c oneBr = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '1 BR', Starting_Price__c = 7500000, Square_FT__c = 650);
        insert new List<Project_Configuration__c>{ threeBr, oneBr };
        Document__c oneBrFolder = readyFolder(oneBr.Id);
        oneBr.Sub_Document__c = uploadInto(oneBrFolder, 'one-br-price-sheet.pdf');
        update oneBr;

        Test.startTest();
        ProjectConfigurationController.ConfigurationData data = ProjectConfigurationController.getConfigurations(skyline);
        Test.stopTest();

        List<String> activeValues = new List<String>();
        for (Schema.PicklistEntry entry : Project_Configuration__c.Unit_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                activeValues.add(entry.getValue());
            }
        }
        System.assert(data.canRead && data.canCreate && data.canEdit, 'Administrators can manage configurations');
        System.assertEquals(activeValues.size(), data.unitTypes.size(), 'Every active Unit Type value is offered');
        System.assertEquals(activeValues[0], data.unitTypes[0].value);
        System.assertEquals(2, data.configurations.size());
        ProjectConfigurationController.Configuration first = data.configurations[0];
        System.assertEquals('1 BR', first.unitType, 'Sorted by unit type');
        System.assertEquals([SELECT Name FROM Project_Configuration__c WHERE Id = :oneBr.Id WITH SYSTEM_MODE].Name, first.name);
        System.assertEquals('one-br-price-sheet.pdf', first.fileName);
        System.assertEquals(FILE_URL, first.fileUrl);
        System.assertEquals(oneBrFolder.Id, first.folderId);
        System.assertEquals(oneBrFolder.Name, first.folderName);
        System.assert(first.folderReady, 'The 1 BR folder exists in OneDrive');
        System.assertNotEquals(null, data.configurations[1].folderId, 'Every configuration has a folder');
        System.assert(!data.configurations[1].folderReady, 'The 3 BR folder is still being created');
        System.assertEquals(null, data.configurations[1].fileUrl);
    }

    @isTest
    static void createsEveryRowInTheOrderSentEachWithItsOwnFolder() {
        Id skyline = projectId('Skyline Towers');

        Test.startTest();
        List<ProjectConfigurationController.Configuration> saved = ProjectConfigurationController.createConfigurations(skyline,
            new List<ProjectConfigurationController.ConfigurationInput>{ row('4.5 BR', null, null), row('2 BR', 9850000.504, 1100) });
        Test.stopTest();

        System.assertEquals(2, saved.size());
        System.assertEquals('4.5 BR', saved[0].unitType, 'Same order as the rows sent, so the component can match its files');
        System.assertEquals('2 BR', saved[1].unitType);
        System.assertEquals(9850000.50, saved[1].startingPrice, 'Rounded to 2 decimals');
        for (ProjectConfigurationController.Configuration config : saved) {
            System.assertNotEquals(null, config.folderId, 'The trigger adds a folder for each new configuration');
            System.assert(!config.folderReady, 'OneDrive creates it in the background');
        }
        System.assertEquals(2, [SELECT COUNT() FROM Project_Configuration__c WHERE Project__c = :skyline WITH SYSTEM_MODE]);
    }

    @isTest
    static void rejectsInvalidRowsWithoutSavingAny() {
        Id skyline = projectId('Skyline Towers');
        List<ProjectConfigurationController.ConfigurationInput> tooMany = new List<ProjectConfigurationController.ConfigurationInput>();
        for (Integer i = 0; i < 51; i++) {
            tooMany.add(row('1 BR', 100, 100));
        }
        ProjectConfigurationController.ConfigurationInput alreadySaved = row('2 BR', 100, 100);
        alreadySaved.id = skyline;
        ProjectConfigurationController.ConfigurationInput withFile = row('2 BR', 100, 100);
        withFile.subDocumentId = [SELECT Id FROM Sub_Document__c WHERE Name = 'harbour-brochure.pdf' WITH SYSTEM_MODE].Id;

        Test.startTest();
        String missingType = createError(skyline, new List<ProjectConfigurationController.ConfigurationInput>{ row('2 BR', 100, 100), row('  ', 100, 100) });
        String unknownType = createError(skyline, rows(row('6 BR', 100, 100)));
        String negativePrice = createError(skyline, rows(row('2 BR', -5, 100)));
        String priceRoundsToZero = createError(skyline, rows(row('2 BR', 0.004, 100)));
        String priceTooLarge = createError(skyline, rows(row('2 BR', Decimal.valueOf('10000000000000'), 100)));
        String fractionalArea = createError(skyline, rows(row('2 BR', 100, 1100.5)));
        String fileOnCreate = createError(skyline, rows(withFile));
        String savedRow = createError(skyline, rows(alreadySaved));
        String empty = createError(skyline, new List<ProjectConfigurationController.ConfigurationInput>());
        String overLimit = createError(skyline, tooMany);
        String notAProject = createError(withFile.subDocumentId, rows(row('2 BR', 100, 100)));
        Test.stopTest();

        System.assert(missingType != null && missingType.startsWith('Row 2:'), 'Points at the row: ' + missingType);
        System.assert(unknownType != null && unknownType.contains('6 BR'), unknownType);
        System.assert(negativePrice != null && negativePrice.contains('starting price'), negativePrice);
        System.assert(priceRoundsToZero != null && priceRoundsToZero.contains('starting price'), 'Checked after rounding: ' + priceRoundsToZero);
        System.assert(priceTooLarge != null && priceTooLarge.contains('13 digits'), priceTooLarge);
        System.assert(fractionalArea != null && fractionalArea.contains('whole number'), fractionalArea);
        System.assert(fileOnCreate != null && fileOnCreate.contains('after the configuration is saved'), fileOnCreate);
        System.assertNotEquals(null, savedRow, 'Saved rows cannot be created again');
        System.assertNotEquals(null, empty);
        System.assert(overLimit != null && overLimit.contains('50'), overLimit);
        System.assert(notAProject != null && notAProject.contains('Project record'), notAProject);
        System.assertEquals(0, [SELECT COUNT() FROM Project_Configuration__c WITH SYSTEM_MODE], 'Nothing is saved when a row is invalid');
    }

    @isTest
    static void allowsOneConfigurationOfEachUnitTypePerProject() {
        Id skyline = projectId('Skyline Towers');
        Id harbour = projectId('Harbour View');
        Project_Configuration__c twoBr = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        Project_Configuration__c threeBr = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR');
        insert new List<Project_Configuration__c>{ twoBr, threeBr };
        String changedTo;

        Test.startTest();
        String alreadyOnProject = createError(skyline, new List<ProjectConfigurationController.ConfigurationInput>{ row('4 BR', 100, 100), row('2 BR', 100, 100) });
        String twiceInOneSave = createError(skyline, new List<ProjectConfigurationController.ConfigurationInput>{ row('5 BR', 100, 100), row('5 BR', 200, 200) });
        String otherProject = createError(harbour, rows(row('2 BR', 100, 100)));
        ProjectConfigurationController.ConfigurationInput edit = row('2 BR', 100, 100);
        edit.id = threeBr.Id;
        try {
            ProjectConfigurationController.updateConfiguration(skyline, edit);
        } catch (AuraHandledException e) {
            changedTo = e.getMessage();
        }
        Test.stopTest();

        System.assert(alreadyOnProject != null && alreadyOnProject.startsWith('Row 2:') && alreadyOnProject.contains('already has a 2 BR configuration'),
            'Points at the row with the unit type the project already has: ' + alreadyOnProject);
        System.assert(twiceInOneSave != null && twiceInOneSave.startsWith('Row 2:') && twiceInOneSave.contains('5 BR'), twiceInOneSave);
        System.assertEquals(null, otherProject, 'Another project can have its own 2 BR');
        System.assert(changedTo != null && changedTo.contains('already has a 2 BR configuration'), changedTo);
        System.assertEquals(2, [SELECT COUNT() FROM Project_Configuration__c WHERE Project__c = :skyline WITH SYSTEM_MODE], 'Nothing else was saved');
        System.assertEquals('3 BR', [SELECT Unit_Type__c FROM Project_Configuration__c WHERE Id = :threeBr.Id WITH SYSTEM_MODE].Unit_Type__c);
    }

    @isTest
    static void updatesValuesAndRemovesTheFileOnlyWhenAsked() {
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR', Starting_Price__c = 100, Square_FT__c = 900);
        insert config;
        Document__c folder = readyFolder(config.Id);
        Id priceSheet = uploadInto(folder, 'price-sheet.pdf');
        config.Sub_Document__c = priceSheet;
        update config;

        ProjectConfigurationController.ConfigurationInput keep = row('3 BR', 12500000, 1180);
        keep.id = config.Id;
        keep.subDocumentId = priceSheet;
        ProjectConfigurationController.ConfigurationInput otherFile = row('3 BR', 12500000, 1180);
        otherFile.id = config.Id;
        otherFile.subDocumentId = [SELECT Id FROM Sub_Document__c WHERE Name = 'harbour-brochure.pdf' WITH SYSTEM_MODE].Id;
        ProjectConfigurationController.ConfigurationInput remove = row('3 BR', 12500000, 1180);
        remove.id = config.Id;
        remove.subDocumentId = priceSheet;
        remove.removeFile = true;

        Test.startTest();
        ProjectConfigurationController.Configuration kept = ProjectConfigurationController.updateConfiguration(skyline, keep);
        ProjectConfigurationController.Configuration notLinked = ProjectConfigurationController.updateConfiguration(skyline, otherFile);
        ProjectConfigurationController.Configuration removed = ProjectConfigurationController.updateConfiguration(skyline, remove);
        Test.stopTest();

        System.assertEquals('3 BR', kept.unitType);
        System.assertEquals(12500000, kept.startingPrice);
        System.assertEquals(1180, kept.squareFt);
        System.assertEquals('price-sheet.pdf', kept.fileName, 'The linked file is kept');
        System.assertEquals(priceSheet, notLinked.subDocumentId, 'An update never links a new file; attachFile does');
        System.assertEquals(null, removed.subDocumentId, 'The file is removed when asked');
    }

    @isTest
    static void keepsAFileThatWasLinkedWhileTheEditWasOpen() {
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        insert config;
        Document__c folder = readyFolder(config.Id);
        Id oldFile = uploadInto(folder, 'old-plan.pdf');
        Id newFile = uploadInto(folder, 'new-plan.pdf');
        // The edit started while old-plan.pdf was linked; an upload has linked new-plan.pdf since
        config.Sub_Document__c = newFile;
        update config;
        ProjectConfigurationController.ConfigurationInput staleRemove = row('2 BR', 5000000, 800);
        staleRemove.id = config.Id;
        staleRemove.subDocumentId = oldFile;
        staleRemove.removeFile = true;

        Test.startTest();
        ProjectConfigurationController.Configuration saved = ProjectConfigurationController.updateConfiguration(skyline, staleRemove);
        Test.stopTest();

        System.assertEquals(5000000, saved.startingPrice, 'The edited values are saved');
        System.assertEquals(newFile, saved.subDocumentId, 'The newer file is not removed');
    }

    @isTest
    static void attachesOnlyFilesUploadedIntoTheConfigurationsFolder() {
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        Project_Configuration__c other = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR');
        insert new List<Project_Configuration__c>{ config, other };
        Id ownFile = uploadInto(readyFolder(config.Id), 'floor-plan.png');
        Id otherFolderFile = uploadInto(readyFolder(other.Id), 'other-floor-plan.png');
        String wrongFolder;
        String notAFile;
        String wrongProject;

        Test.startTest();
        ProjectConfigurationController.Configuration attached = ProjectConfigurationController.attachFile(skyline, config.Id, ownFile);
        try {
            ProjectConfigurationController.attachFile(skyline, config.Id, otherFolderFile);
        } catch (AuraHandledException e) {
            wrongFolder = e.getMessage();
        }
        try {
            ProjectConfigurationController.attachFile(skyline, config.Id, skyline);
        } catch (AuraHandledException e) {
            notAFile = e.getMessage();
        }
        try {
            ProjectConfigurationController.attachFile(projectId('Harbour View'), config.Id, ownFile);
        } catch (AuraHandledException e) {
            wrongProject = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals('floor-plan.png', attached.fileName);
        System.assertEquals(ownFile, [SELECT Sub_Document__c FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Sub_Document__c);
        System.assert(wrongFolder != null && wrongFolder.contains('folder'), wrongFolder);
        System.assert(notAFile != null && notAFile.contains('not valid'), notAFile);
        System.assert(wrongProject != null && wrongProject.contains('not on this project'), wrongProject);
    }

    @isTest
    static void reportsFolderStatusAndRecreatesAMissingFolder() {
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        insert config;

        Test.startTest();
        ProjectConfigurationController.FolderStatus pending = ProjectConfigurationController.getFolderStatus(skyline, new List<Id>{ config.Id })[0];
        readyFolder(config.Id);
        ProjectConfigurationController.FolderStatus ready = ProjectConfigurationController.getFolderStatus(skyline, new List<Id>{ config.Id })[0];
        delete [SELECT Id FROM Document__c WHERE Project_Configuration__c = :config.Id];
        ProjectConfigurationController.FolderStatus missing = ProjectConfigurationController.getFolderStatus(skyline, new List<Id>{ config.Id })[0];
        ProjectConfigurationController.FolderStatus requested = ProjectConfigurationController.requestFolder(skyline, config.Id);
        List<ProjectConfigurationController.FolderStatus> otherProject = ProjectConfigurationController.getFolderStatus(projectId('Harbour View'), new List<Id>{ config.Id });
        Test.stopTest();

        System.assert(pending.folderId != null && !pending.ready, 'Created by the trigger, not yet in OneDrive');
        System.assert(ready.ready);
        System.assertEquals(null, missing.folderId);
        System.assertNotEquals(null, requested.folderId, 'A missing folder is created again');
        System.assertEquals(0, otherProject.size(), 'Only configurations of the given project are reported');
    }

    @isTest
    static void refusesToUpdateAnotherProjectsConfiguration() {
        Project_Configuration__c config = new Project_Configuration__c(Project__c = projectId('Harbour View'), Unit_Type__c = '2 BR');
        insert config;
        ProjectConfigurationController.ConfigurationInput change = row('3 BR', null, null);
        change.id = config.Id;
        String otherProject;
        String noRecord;

        Test.startTest();
        try {
            ProjectConfigurationController.updateConfiguration(projectId('Skyline Towers'), change);
        } catch (AuraHandledException e) {
            otherProject = e.getMessage();
        }
        try {
            ProjectConfigurationController.updateConfiguration(projectId('Skyline Towers'), row('3 BR', null, null));
        } catch (AuraHandledException e) {
            noRecord = e.getMessage();
        }
        Test.stopTest();

        System.assertNotEquals(null, otherProject);
        System.assertNotEquals(null, noRecord);
        System.assertEquals('2 BR', [SELECT Unit_Type__c FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Unit_Type__c);
    }

    @isTest
    static void usersWithoutAccessSeeNothingAndCannotSave() {
        Profile minimumAccess = [SELECT Id FROM Profile WHERE UserType = 'Standard' AND PermissionsModifyAllData = false AND Name = 'Minimum Access - Salesforce' LIMIT 1];
        User viewer = new User(
            Alias = 'pcnoacc',
            Email = 'pc.noaccess@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'No Access',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimumAccess.Id,
            TimeZoneSidKey = 'Asia/Colombo',
            Username = 'pc.noaccess.' + System.currentTimeMillis() + '@example.com'
        );
        insert viewer;
        Id skyline = projectId('Skyline Towers');
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert config;
        }
        ProjectConfigurationController.ConfigurationData data;
        String createMessage;
        String updateMessage;
        String statusMessage;

        Test.startTest();
        System.runAs(viewer) {
            data = ProjectConfigurationController.getConfigurations(skyline);
            createMessage = createError(skyline, rows(row('2 BR', 100, 100)));
            try {
                ProjectConfigurationController.updateConfiguration(skyline, row('2 BR', 100, 100));
            } catch (AuraHandledException e) {
                updateMessage = e.getMessage();
            }
            try {
                ProjectConfigurationController.getFolderStatus(skyline, new List<Id>{ config.Id });
            } catch (AuraHandledException e) {
                statusMessage = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(false, data.canRead, 'No object access, so nothing is shown');
        System.assertEquals(0, data.configurations.size());
        System.assert(createMessage != null && createMessage.contains('permission'), createMessage);
        System.assert(updateMessage != null && updateMessage.contains('permission'), updateMessage);
        System.assert(statusMessage != null && statusMessage.contains('access'), statusMessage);
        System.assertEquals(1, [SELECT COUNT() FROM Project_Configuration__c WITH SYSTEM_MODE]);
    }
}