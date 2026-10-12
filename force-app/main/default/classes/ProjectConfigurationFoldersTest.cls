@isTest
private class ProjectConfigurationFoldersTest {

    @testSetup
    static void setup() {
        Project__c skyline = new Project__c(Name = 'Skyline Towers', Active__c = true, Document_Id__c = 'SKYLINE-ROOT');
        Project__c harbour = new Project__c(Name = 'Harbour: View / Phase 1', Active__c = true, Document_Id__c = 'HARBOUR-ROOT');
        // Its own OneDrive folder has not been created yet
        Project__c brandNew = new Project__c(Name = 'Brand New Residences', Active__c = true);
        insert new List<Project__c>{ skyline, harbour, brandNew };
        // Skyline already has its "Project Configurations" folder; Harbour does not
        insert new Document__c(Name = 'Project Configurations', Project__c = skyline.Id, Document_Id__c = 'SKYLINE-CONFIGURATIONS');
    }

    private static Id projectId(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static List<Document__c> foldersOf(Id configurationId) {
        return [
            SELECT Id, Name, Parent_Document__c, Project__c
            FROM Document__c
            WHERE Project_Configuration__c = :configurationId
            WITH SYSTEM_MODE
        ];
    }

    private static Project_Configuration__c fromJson(String body) {
        // Name is an auto-number, so these in-memory records are built from JSON
        return (Project_Configuration__c) JSON.deserialize(body, Project_Configuration__c.class);
    }

    @isTest
    static void createsAFolderForEachNewConfigurationInsideProjectConfigurations() {
        Id skyline = projectId('Skyline Towers');

        Test.startTest();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        insert config;
        Test.stopTest();

        String configurationNumber = [SELECT Name FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Name;
        Id parent = [SELECT Id FROM Document__c WHERE Document_Id__c = 'SKYLINE-CONFIGURATIONS' WITH SYSTEM_MODE].Id;
        List<Document__c> folders = foldersOf(config.Id);
        System.assertEquals(1, folders.size(), 'One folder per configuration');
        System.assertEquals(configurationNumber + ' - Skyline Towers - 2 BR', folders[0].Name);
        System.assertEquals(parent, folders[0].Parent_Document__c, 'Created inside Project Configurations');
        System.assertEquals(null, folders[0].Project__c, 'Listed inside Project Configurations, not beside it');
        System.assertEquals(new List<Id>{ folders[0].Id }, ProjectConfigurationFolders.lastQueued, 'Queued for OneDrive');
        System.assertEquals(1, [SELECT COUNT() FROM Document__c WHERE Name = 'Project Configurations' AND Project__c = :skyline WITH SYSTEM_MODE],
            'The existing Project Configurations folder is reused');
    }

    @isTest
    static void createsProjectConfigurationsFirstWhenTheProjectHasNone() {
        Id harbour = projectId('Harbour: View / Phase 1');

        Test.startTest();
        insert new List<Project_Configuration__c>{
            new Project_Configuration__c(Project__c = harbour, Unit_Type__c = '3.5 BR'),
            new Project_Configuration__c(Project__c = harbour, Unit_Type__c = '4 BR')
        };
        Test.stopTest();

        List<Document__c> parents = [SELECT Id FROM Document__c WHERE Name = 'Project Configurations' AND Project__c = :harbour WITH SYSTEM_MODE];
        System.assertEquals(1, parents.size(), 'One Project Configurations folder per project');
        List<Document__c> folders = [
            SELECT Name, Parent_Document__c
            FROM Document__c
            WHERE Project_Configuration__r.Project__c = :harbour
            WITH SYSTEM_MODE
        ];
        System.assertEquals(2, folders.size());
        for (Document__c folder : folders) {
            System.assertEquals(parents[0].Id, folder.Parent_Document__c);
            System.assert(folder.Name.contains(' - Harbour_ View _ Phase 1 - '), 'Characters OneDrive refuses are replaced: ' + folder.Name);
        }
        System.assertEquals(3, ProjectConfigurationFolders.lastQueued.size());
        System.assertEquals(parents[0].Id, ProjectConfigurationFolders.lastQueued[0], 'OneDrive creates the parent before the folders inside it');
    }

    @isTest
    static void neverCreatesASecondFolderForAConfiguration() {
        Project_Configuration__c config = new Project_Configuration__c(Project__c = projectId('Skyline Towers'), Unit_Type__c = '5 BR');
        insert config;
        ProjectConfigurationFolders.lastQueued = new List<Id>();

        Test.startTest();
        ProjectConfigurationFolders.createFolders(new Set<Id>{ config.Id });
        ProjectConfigurationFolders.createFolders(null);
        Test.stopTest();

        System.assertEquals(0, ProjectConfigurationFolders.lastQueued.size(), 'Nothing to create or queue');
        System.assertEquals(1, foldersOf(config.Id).size());
    }

    @isTest
    static void waitsForTheProjectsOwnFolderBeforeAddingAny() {
        Project__c brandNew = [SELECT Id FROM Project__c WHERE Name = 'Brand New Residences' WITH SYSTEM_MODE];
        Project_Configuration__c config = new Project_Configuration__c(Project__c = brandNew.Id, Unit_Type__c = '2 BR');
        insert config;
        Integer beforeRoot = foldersOf(config.Id).size();
        Integer parentsBeforeRoot = [SELECT COUNT() FROM Document__c WHERE Project__c = :brandNew.Id AND Name = 'Project Configurations' WITH SYSTEM_MODE];

        // The project's folder job has now run
        brandNew.Document_Id__c = 'BRAND-NEW-ROOT';
        update brandNew;

        Test.startTest();
        ProjectConfigurationFolders.ensureFolders(new Set<Id>{ config.Id });
        Test.stopTest();

        System.assertEquals(0, beforeRoot, 'No folder can be placed while the project has no OneDrive folder');
        System.assertEquals(0, parentsBeforeRoot, 'So no Project Configurations folder is started either');
        System.assertEquals(1, foldersOf(config.Id).size(), 'Added once the project folder exists');
        System.assertEquals(2, ProjectConfigurationFolders.lastQueued.size(), 'Project Configurations and the configuration folder');
    }

    @isTest
    static void prefersTheProjectConfigurationsFolderThatExistsInOneDrive() {
        Id skyline = projectId('Skyline Towers');
        Document__c neverCreated = new Document__c(Name = 'Project Configurations', Project__c = skyline);
        insert neverCreated;
        Test.setCreatedDate(neverCreated.Id, System.now().addDays(-1));

        Test.startTest();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '1 BR');
        insert config;
        Test.stopTest();

        Id ready = [SELECT Id FROM Document__c WHERE Document_Id__c = 'SKYLINE-CONFIGURATIONS' WITH SYSTEM_MODE].Id;
        System.assertEquals(ready, foldersOf(config.Id)[0].Parent_Document__c, 'The older folder that never reached OneDrive is not used');
    }

    @isTest
    static void placesFoldersInsideAParentThatIsStillBeingCreated() {
        Id harbour = projectId('Harbour: View / Phase 1');
        Document__c pendingParent = new Document__c(Name = 'Project Configurations', Project__c = harbour);
        insert pendingParent;

        Test.startTest();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = harbour, Unit_Type__c = '3 BR');
        insert config;
        Test.stopTest();

        List<Document__c> folders = foldersOf(config.Id);
        System.assertEquals(pendingParent.Id, folders[0].Parent_Document__c, 'No second Project Configurations folder');
        System.assertEquals(new List<Id>{ folders[0].Id }, ProjectConfigurationFolders.lastQueued, 'Queued (with a delay) behind the parent');
    }

    @isTest
    static void findsStalledFoldersWithAStalledParentFirst() {
        Id skyline = projectId('Skyline Towers');
        Id harbour = projectId('Harbour: View / Phase 1');
        Project_Configuration__c readyParent = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '2 BR');
        Project_Configuration__c stalledParent = new Project_Configuration__c(Project__c = harbour, Unit_Type__c = '3 BR');
        Project_Configuration__c recent = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '4 BR');
        insert new List<Project_Configuration__c>{ readyParent, stalledParent, recent };
        Datetime longAgo = System.now().addMinutes(-10);
        Document__c readyParentFolder = foldersOf(readyParent.Id)[0];
        Document__c stalledParentFolder = foldersOf(stalledParent.Id)[0];
        Test.setCreatedDate(readyParentFolder.Id, longAgo);
        Test.setCreatedDate(stalledParentFolder.Id, longAgo);
        Test.setCreatedDate(stalledParentFolder.Parent_Document__c, longAgo);

        Test.startTest();
        List<Id> stalled = ProjectConfigurationFolders.stalledFolders(new Set<Id>{ readyParent.Id, stalledParent.Id, recent.Id });
        Test.stopTest();

        System.assertEquals(3, stalled.size(), 'The recent folder is still being created, so it is left alone');
        System.assert(stalled.contains(readyParentFolder.Id));
        Integer parentAt = stalled.indexOf(stalledParentFolder.Parent_Document__c);
        System.assert(parentAt >= 0 && parentAt < stalled.indexOf(stalledParentFolder.Id), 'A stalled parent is queued before its folder');
    }

    @isTest
    static void savesTheConfigurationAndLeavesNoHalfMadeFoldersWhenTheFolderStepFails() {
        Id harbour = projectId('Harbour: View / Phase 1');
        ProjectConfigurationFolders.simulateFailure = true;

        Test.startTest();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = harbour, Unit_Type__c = '2 BR');
        insert config;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE], 'The configuration is saved');
        System.assertEquals(0, [SELECT COUNT() FROM Document__c WHERE Project__c = :harbour AND Name = 'Project Configurations' WITH SYSTEM_MODE],
            'The parent inserted before the failure is rolled back');
        System.assertEquals(0, foldersOf(config.Id).size());
    }

    @isTest
    static void keepsTheNumberAndUnitTypeWholeInFolderNames() {
        Project_Configuration__c longName = fromJson('{"Name":"PC-0042","Unit_Type__c":"3.5 BR","Project__r":{"Name":"' + 'Grand Residences '.repeat(5) + '"}}');
        Project_Configuration__c endsWithDot = fromJson('{"Name":"PC-0043","Project__r":{"Name":"Grand Tower."}}');
        Project_Configuration__c noProject = fromJson('{"Name":"PC-0044","Unit_Type__c":"1 BR"}');

        String shortened = ProjectConfigurationFolders.folderName(longName);
        System.assert(shortened.length() <= 80, 'Fits a Document name: ' + shortened.length());
        System.assert(shortened.startsWith('PC-0042 - Grand Residences'), shortened);
        System.assert(shortened.endsWith(' - 3.5 BR'), 'The unit type is never cut off: ' + shortened);
        System.assertEquals('PC-0043 - Grand Tower', ProjectConfigurationFolders.folderName(endsWithDot), 'OneDrive refuses a trailing dot');
        System.assertEquals('PC-0044 - 1 BR', ProjectConfigurationFolders.folderName(noProject));
    }
}