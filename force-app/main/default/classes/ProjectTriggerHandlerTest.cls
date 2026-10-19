@isTest
private class ProjectTriggerHandlerTest {

    // Refuses the SharePoint folder call, so the folder job queued by the project insert does nothing and these tests
    // count only the documents they create themselves
    private class SharePointMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // A test token and library id, so the folder job never signs in or looks the library up
    private static void mockSharePoint() {
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, new SharePointMock());
    }

    @testSetup
    static void setup() {
        Document_Master__c master = new Document_Master__c(Name = 'Project');
        insert master;
        insert new Document_category__c(Name = 'Marketing', Document_Master__c = master.Id);
    }

    @isTest
    static void insertQueuesOneFolderJobForAllProjects() {
        mockSharePoint();
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < 5; i++) {
            projects.add(new Project__c(Name = 'Test Project ' + i, Email__c = 'projects@example.com', Location__Latitude__s = 6.9271, Location__Longitude__s = 79.8612));
        }

        Test.startTest();
        insert projects;
        Integer queuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, queuedJobs, 'One SharePoint job should be queued for the whole insert');
        System.assertEquals(5, [SELECT COUNT() FROM Project__c WITH SYSTEM_MODE], 'Projects must be saved even though folder creation runs async');
    }

    @isTest
    static void createsOneDocumentPerProjectCategory() {
        mockSharePoint();
        Project__c project = new Project__c(Name = 'Skyline Towers', Email__c = 'projects@example.com', Location__Latitude__s = 6.9271, Location__Longitude__s = 79.8612);
        insert project;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Project__c>{ project });
        Test.stopTest();

        List<Document__c> docs = [SELECT Name, Project__c FROM Document__c WHERE Project__c = :project.Id WITH SYSTEM_MODE];
        System.assertEquals(1, docs.size(), 'One Document should be created per Project category');
        System.assertEquals('Marketing', docs[0].Name);
    }

    @isTest
    static void createsProjectDocumentWhenNoCategories() {
        mockSharePoint();
        delete [SELECT Id FROM Document_category__c WITH SYSTEM_MODE];
        Project__c project = new Project__c(Name = 'Harbour View', Email__c = 'projects@example.com', Location__Latitude__s = 6.9271, Location__Longitude__s = 79.8612);
        insert project;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Project__c>{ project });
        Test.stopTest();

        List<Document__c> docs = [SELECT Name FROM Document__c WHERE Project__c = :project.Id WITH SYSTEM_MODE];
        System.assertEquals(1, docs.size(), 'Without categories the project gets a single document');
        System.assertEquals('Harbour View', docs[0].Name);
    }

    @isTest
    static void emptyListQueuesNothing() {
        Test.startTest();
        ProjectTriggerHandler.handleAfterInsert(new List<Project__c>());
        Integer queuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queuedJobs, 'No job should be queued when there are no projects');
    }
}