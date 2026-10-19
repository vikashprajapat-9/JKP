// Test records that pass the org's required fields, whatever they are: every required field the test does not set gets a
// value of its type (fields are made required in Setup from time to time, for example Project's Customer Support Email
// and Location on 2026-10-06, which broke every test that inserted a project with only its name).
@isTest
public class TestRecordDefaults {

    // A project with this name, active or not, and a value in every other required field
    public static Project__c project(String name, Boolean active) {
        Project__c record = new Project__c(Name = name, Active__c = active);
        fillRequired(record);
        return record;
    }

    // Gives every required, creatable field without a default that the record leaves empty a value of its type
    public static SObject fillRequired(SObject record) {
        for (SObjectField field : record.getSObjectType().getDescribe().fields.getMap().values()) {
            DescribeFieldResult describe = field.getDescribe();
            if (describe.isNillable() || !describe.isCreateable() || describe.isDefaultedOnCreate() || record.get(field) != null) {
                continue;
            }
            Object value = sample(describe);
            if (value != null) {
                record.put(field, value);
            }
        }
        return record;
    }

    private static Object sample(DescribeFieldResult describe) {
        switch on describe.getType() {
            when STRING, TEXTAREA {
                return 'Test ' + describe.getName().left(30);
            }
            when EMAIL {
                return 'test.record@example.com';
            }
            when PHONE {
                return '0771234567';
            }
            when URL {
                return 'https://example.com';
            }
            when DOUBLE, CURRENCY, PERCENT {
                // A geolocation's latitude and longitude are numbers too: Colombo
                return describe.getName().endsWith('__Longitude__s') ? 79.8612 : 6.9271;
            }
            when INTEGER {
                return 1;
            }
            when DATE {
                return Date.today();
            }
            when DATETIME {
                return Datetime.now();
            }
            when PICKLIST {
                for (PicklistEntry entry : describe.getPicklistValues()) {
                    if (entry.isActive()) {
                        return entry.getValue();
                    }
                }
                return null;
            }
            when else {
                return null;
            }
        }
    }
}