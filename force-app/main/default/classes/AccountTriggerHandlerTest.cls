@isTest
private class AccountTriggerHandlerTest {

    // The org's channel partner record type, as the Partner Registration Setting names it
    private static Schema.RecordTypeInfo partnerType() {
        return Schema.SObjectType.Account.getRecordTypeInfosById().get(partnerPortalRegistrationController.partnerRecordTypeId());
    }

    private static Id otherAccountTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isActive() && !info.isMaster() && info.getRecordTypeId() != partnerType().getRecordTypeId()) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    // Refuses every SharePoint call, so a folder job these tests start does nothing
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

    // A Document Master for channel partner accounts, its Record Type written in other capitals than the record type
    private static void createChannelPartnerMaster() {
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id),
            new Document_category__c(Name = 'NIC, TIN and passport', Document_Master__c = master.Id)
        };
    }

    @isTest
    static void queuesFoldersForANewChannelPartnerAccount() {
        createChannelPartnerMaster();
        mockSharePoint();

        Test.startTest();
        insert new Account(Name = 'Harbour Realty', RecordTypeId = partnerType().getRecordTypeId());
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, queued, 'Its folder and Documents are made the way a project\'s are');
    }

    @isTest
    static void leavesOtherAccountsAlone() {
        createChannelPartnerMaster();
        Id customerType = otherAccountTypeId();
        System.assertNotEquals(null, customerType, 'The org has a second Account record type (Customer) to compare with');

        Test.startTest();
        insert new List<Account>{
            new Account(Name = 'A Customer', RecordTypeId = customerType),
            new Account(Name = 'Registered Partner', RecordTypeId = partnerType().getRecordTypeId(), Document_Id__c = 'folder-already-made')
        };
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queued, 'No master for customers, and a portal registration already has its folder');
    }

    @isTest
    static void queuesNothingWithoutAnyDocumentMaster() {
        Test.startTest();
        insert new Account(Name = 'Harbour Realty', RecordTypeId = partnerType().getRecordTypeId());
        Integer queued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queued);
    }

    @isTest
    static void createsADocumentPerCategoryInAnyCapitals() {
        createChannelPartnerMaster();
        mockSharePoint();
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerType().getRecordTypeId(), Document_Id__c = 'root-folder');
        insert partner;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Account>{ partner });
        Test.stopTest();

        List<Document__c> documents = [SELECT Name FROM Document__c WHERE Account__c = :partner.Id ORDER BY Name];
        System.assertEquals(2, documents.size(), '"Channel partner" on the master matches the "Channel Partner" record type');
        System.assertEquals('BR, VAT Certificate', documents[0].Name);
        System.assertEquals('NIC, TIN and passport', documents[1].Name);
        System.assertEquals(new Set<String>{ 'channel partner' }, DocumentCreationHandler.recordTypesWithDocuments());
        System.assertEquals(2, DocumentCreationHandler.categoriesForRecordType('CHANNEL PARTNER').size());
        System.assertEquals(0, DocumentCreationHandler.categoriesForRecordType('Customer').size());
    }

    @isTest
    static void ignoresOrphanCategoriesAndAccountMastersWithoutARecordType() {
        createChannelPartnerMaster();
        mockSharePoint();
        Document_Master__c generic = new Document_Master__c(Name = 'Account');
        insert generic;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'Agreements', Document_Master__c = generic.Id),
            new Document_category__c(Name = 'Left Behind')
        };
        Account partner = new Account(Name = 'Harbour Realty', RecordTypeId = partnerType().getRecordTypeId(), Document_Id__c = 'root-folder');
        insert partner;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Account>{ partner });
        Test.stopTest();

        List<Document__c> documents = [SELECT Name FROM Document__c WHERE Account__c = :partner.Id ORDER BY Name];
        System.assertEquals(2, documents.size(), 'Only the Channel Partner categories: ' + documents);
        System.assertEquals('BR, VAT Certificate', documents[0].Name);
    }

    @isTest
    static void folderNamesAreOnesSharePointAccepts() {
        System.assertEquals('M_s Perera Holdings', SharePointDocumentManagerController.folderName(' M/s Perera Holdings. '));
        System.assertEquals('A_B_C', SharePointDocumentManagerController.folderName('A:B*C'));
        System.assertEquals('Untitled', SharePointDocumentManagerController.folderName(' . '));
    }
}