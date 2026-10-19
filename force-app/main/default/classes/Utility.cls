public with sharing class Utility {

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistValues( String objectApiName, String fieldApiName ) {
        List<PicklistOption> options = new List<PicklistOption>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectApiName)) {
            throw new AuraHandledException(
                'Invalid Object API Name: ' + objectApiName
            );
        }
        Schema.SObjectType sObjectType = globalDescribe.get(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApiName)) {
            throw new AuraHandledException(
                'Invalid Field API Name: ' + fieldApiName
            );
        }
        Schema.DescribeFieldResult fieldDescribe =  fieldMap.get(fieldApiName).getDescribe();
        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
            throw new AuraHandledException(
                fieldApiName + ' is not a Picklist field.'
            );
        }

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add( new PicklistOption( entry.getLabel(), entry.getValue() ) );
            }
        }

        return options;
    }

    private static List<Utility.PicklistOption> getReferAndEarnFilterOptions() {
        List<Utility.PicklistOption> options = new List<Utility.PicklistOption>();
        String labelValue = System.Label.Refer_and_Earn_Filter_Options;
        if (String.isBlank(labelValue)) {
            return options;
        }

        Set<String> seenValues = new Set<String>();
        for (String rawOption : labelValue.split(',')) {
            String option = rawOption.trim();
            if (String.isBlank(option) || !seenValues.add(option)) {
                continue;
            }
            options.add(new Utility.PicklistOption(option, option));
        }
        return options;
    }
}