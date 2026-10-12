// Content of the channel partner portal's About Us and Terms & Conditions pages, kept on the Portal Info record whose
// Type is Channel partner. Without sharing: partners have no record access to Portal Info, and only this record's
// content is returned.
public without sharing class partnerWebPortalInfoController {

    // Portal_Info__c.Type__c of the channel partner portal's record (one record per Type, see PortalInfoTrigger)
    private static final String CHANNEL_PARTNER = 'Channel partner';

    public class PortalInfo {
        // Rich text (HTML) from the record
        @AuraEnabled public String aboutUs;
        @AuraEnabled public String termsAndConditions;
    }

    // The fields are blank until the record is created
    @AuraEnabled(cacheable=true)
    public static PortalInfo getChannelPartnerInfo() {
        PortalInfo info = new PortalInfo();
        for (Portal_Info__c record : [
            SELECT About_Us__c, Terms_Condition__c
            FROM Portal_Info__c
            WHERE Type__c = :CHANNEL_PARTNER
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ]) {
            info.aboutUs = record.About_Us__c;
            info.termsAndConditions = record.Terms_Condition__c;
        }
        return info;
    }
}