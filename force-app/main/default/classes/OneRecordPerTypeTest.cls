@isTest
private class OneRecordPerTypeTest {

    @testSetup
    static void setup() {
        insert new List<Project__c>{
            new Project__c(Name = 'Skyline Towers', Active__c = true),
            new Project__c(Name = 'Harbour View', Active__c = true)
        };
    }

    private static Id projectId(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    // The error on the record, or null when it was saved
    private static String errorOf(Database.SaveResult result) {
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    @isTest
    static void allowsOnePortalInfoRecordForEachPortal() {
        Portal_Info__c channelPartner = new Portal_Info__c(Type__c = 'Channel partner', About_Us__c = '<p>About</p>');
        insert channelPartner;

        Test.startTest();
        String secondChannelPartner = errorOf(Database.insert(new Portal_Info__c(Type__c = 'Channel partner'), false));
        Portal_Info__c customer = new Portal_Info__c(Type__c = 'Customer');
        String firstCustomer = errorOf(Database.insert(customer, false));
        String customerToChannelPartner = errorOf(Database.update(new Portal_Info__c(Id = customer.Id, Type__c = 'Channel partner'), false));
        String withoutType = errorOf(Database.insert(new Portal_Info__c(About_Us__c = '<p>No portal</p>'), false));
        String contentEdit = errorOf(Database.update(new Portal_Info__c(Id = channelPartner.Id, Terms_Condition__c = '<p>Terms</p>'), false));
        Test.stopTest();

        System.assert(secondChannelPartner != null && secondChannelPartner.contains('Only one Portal Info record is allowed for Channel partner'), secondChannelPartner);
        System.assertEquals(null, firstCustomer, 'The Customer portal gets its own record');
        System.assert(customerToChannelPartner != null && customerToChannelPartner.contains('Channel partner'), customerToChannelPartner);
        System.assert(withoutType != null && withoutType.contains('Choose which portal'), 'Type is required: ' + withoutType);
        System.assertEquals(null, contentEdit, 'The existing record can still be edited');
        System.assertEquals(2, [SELECT COUNT() FROM Portal_Info__c WITH SYSTEM_MODE], 'Only the two portals have a record');
    }

    @isTest
    static void refusesTheSecondRecordOfATypeInOneSave() {
        Test.startTest();
        List<Database.SaveResult> results = Database.insert(new List<Portal_Info__c>{
            new Portal_Info__c(Type__c = 'Customer'),
            new Portal_Info__c(Type__c = 'Customer'),
            new Portal_Info__c(Type__c = 'Channel partner')
        }, false);
        Test.stopTest();

        System.assertEquals(null, errorOf(results[0]), 'The first Customer record is saved');
        System.assert(errorOf(results[1]) != null && errorOf(results[1]).contains('Customer'), errorOf(results[1]));
        System.assertEquals(null, errorOf(results[2]));
    }

    @isTest
    static void allowsOneAmenityOfEachTypePerProject() {
        Id skyline = projectId('Skyline Towers');
        Id harbour = projectId('Harbour View');
        Amenties__c pool = new Amenties__c(Project__c = skyline, Type__c = 'Swimming Pool');
        Amenties__c gym = new Amenties__c(Project__c = skyline, Type__c = 'Sky Gym');
        insert new List<Amenties__c>{ pool, gym };

        Test.startTest();
        String secondPool = errorOf(Database.insert(new Amenties__c(Project__c = skyline, Type__c = 'Swimming Pool'), false));
        String poolElsewhere = errorOf(Database.insert(new Amenties__c(Project__c = harbour, Type__c = 'Swimming Pool'), false));
        String gymToPool = errorOf(Database.update(new Amenties__c(Id = gym.Id, Type__c = 'Swimming Pool'), false));
        // Swapping two types in one save leaves one of each, so it is allowed
        List<Database.SaveResult> swap = Database.update(new List<Amenties__c>{
            new Amenties__c(Id = pool.Id, Type__c = 'Sky Gym'),
            new Amenties__c(Id = gym.Id, Type__c = 'Swimming Pool')
        }, false);
        Test.stopTest();

        System.assert(secondPool != null && secondPool.contains('already has the Swimming Pool amenity'), secondPool);
        System.assertEquals(null, poolElsewhere, 'Another project can have its own Swimming Pool');
        System.assert(gymToPool != null && gymToPool.contains('Swimming Pool'), gymToPool);
        System.assertEquals(null, errorOf(swap[0]));
        System.assertEquals(null, errorOf(swap[1]));
        System.assertEquals('Sky Gym', [SELECT Type__c FROM Amenties__c WHERE Id = :pool.Id WITH SYSTEM_MODE].Type__c);
    }

    @isTest
    static void aTypeKeptInTheSameSaveStillCounts() {
        Id skyline = projectId('Skyline Towers');
        Amenties__c pool = new Amenties__c(Project__c = skyline, Type__c = 'Swimming Pool');
        Amenties__c gym = new Amenties__c(Project__c = skyline, Type__c = 'Sky Gym');
        insert new List<Amenties__c>{ pool, gym };

        Test.startTest();
        // The pool keeps its type while the gym tries to take it
        List<Database.SaveResult> results = Database.update(new List<Amenties__c>{
            new Amenties__c(Id = pool.Id, Type__c = 'Swimming Pool'),
            new Amenties__c(Id = gym.Id, Type__c = 'Swimming Pool')
        }, false);
        Test.stopTest();

        System.assertEquals(null, errorOf(results[0]), 'Editing a record without changing its type is always allowed');
        System.assert(errorOf(results[1]) != null && errorOf(results[1]).contains('Swimming Pool'), errorOf(results[1]));
    }

    @isTest
    static void aRestoredRecordCannotDuplicateAType() {
        Id skyline = projectId('Skyline Towers');
        Amenties__c oldPool = new Amenties__c(Project__c = skyline, Type__c = 'Swimming Pool');
        Amenties__c oldGym = new Amenties__c(Project__c = skyline, Type__c = 'Sky Gym');
        Portal_Info__c oldInfo = new Portal_Info__c(Type__c = 'Channel partner');
        Project_Configuration__c oldThreeBr = new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR');
        insert new List<SObject>{ oldPool, oldGym, oldInfo, oldThreeBr };
        delete new List<SObject>{ oldPool, oldGym, oldInfo, oldThreeBr };
        // Replacements were created while the old records were in the Recycle Bin (none for the gym)
        insert new List<SObject>{
            new Amenties__c(Project__c = skyline, Type__c = 'Swimming Pool'),
            new Portal_Info__c(Type__c = 'Channel partner'),
            new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR')
        };

        Test.startTest();
        List<Database.UndeleteResult> results = Database.undelete(new List<Id>{ oldPool.Id, oldGym.Id, oldInfo.Id, oldThreeBr.Id }, false);
        Test.stopTest();

        System.assert(!results[0].isSuccess() && results[0].getErrors()[0].getMessage().contains('already has the Swimming Pool amenity'),
            'A restored amenity cannot repeat a type the project has again');
        System.assert(results[1].isSuccess(), 'Restoring a record whose type is free is allowed');
        System.assert(!results[2].isSuccess() && results[2].getErrors()[0].getMessage().contains('Channel partner'));
        System.assert(!results[3].isSuccess() && results[3].getErrors()[0].getMessage().contains('already has a 3 BR configuration'));
        System.assertEquals(1, [SELECT COUNT() FROM Portal_Info__c WHERE Type__c = 'Channel partner' WITH SYSTEM_MODE]);
        System.assertEquals(1, [SELECT COUNT() FROM Project_Configuration__c WHERE Project__c = :skyline AND Unit_Type__c = '3 BR' WITH SYSTEM_MODE]);
    }

    @isTest
    static void allowsOneConfigurationOfEachUnitTypePerProject() {
        Id skyline = projectId('Skyline Towers');
        insert new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR');

        Test.startTest();
        String secondThreeBr = errorOf(Database.insert(new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '3 BR'), false));
        String fourBr = errorOf(Database.insert(new Project_Configuration__c(Project__c = skyline, Unit_Type__c = '4 BR'), false));
        Test.stopTest();

        System.assert(secondThreeBr != null && secondThreeBr.contains('already has a 3 BR configuration'), secondThreeBr);
        System.assertEquals(null, fourBr);
    }
}