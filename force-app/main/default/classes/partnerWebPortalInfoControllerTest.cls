@isTest
private class partnerWebPortalInfoControllerTest {

    @isTest
    static void partnersSeeTheChannelPartnerContent() {
        insert new List<Portal_Info__c>{
            new Portal_Info__c(Type__c = 'Channel partner', About_Us__c = '<p>We build lasting value.</p>', Terms_Condition__c = '<p>Use of this portal…</p>'),
            new Portal_Info__c(Type__c = 'Customer', About_Us__c = '<p>For customers</p>', Terms_Condition__c = '<p>Customer terms</p>')
        };
        User partner = PartnerPortalTestUser.create();
        partnerWebPortalInfoController.PortalInfo info;

        Test.startTest();
        System.runAs(partner) {
            info = partnerWebPortalInfoController.getChannelPartnerInfo();
        }
        Test.stopTest();

        System.assertNotEquals(null, info, 'Partners can read the content without access to Portal Info records');
        System.assertEquals('<p>We build lasting value.</p>', info.aboutUs, 'The Channel partner record, not the Customer one');
        System.assertEquals('<p>Use of this portal…</p>', info.termsAndConditions);
    }

    @isTest
    static void returnsNothingBeforeTheRecordExists() {
        insert new Portal_Info__c(Type__c = 'Customer', About_Us__c = '<p>For customers</p>');

        Test.startTest();
        partnerWebPortalInfoController.PortalInfo info = partnerWebPortalInfoController.getChannelPartnerInfo();
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertEquals(null, info.aboutUs, 'The pages show their "coming soon" note');
        System.assertEquals(null, info.termsAndConditions);
    }
}