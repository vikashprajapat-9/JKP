@RestResource(urlMapping='/api/picklist-values')
global without sharing class API_PicklistValues {

    @HttpGet
    global static void getPicklistValues() {
        RestResponse res = RestContext.response;
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
           List<Utility.PicklistOption> visitTypeOptions  = Utility.getPicklistValues('Visit__c', 'Visit_Type__c');
           List<Utility.PicklistOption> referAndEarnFilterOptions = getReferAndEarnFilterOptions();
            // List<Utility.PicklistOption> supportTypeOptions    = Utility.getPicklistValues('Case', 'Type');
            // List<Utility.PicklistOption> supportSubTypeOptions = Utility.getPicklistValues('Case', 'Sub_Type__c');
            List<LocationOptionWrapper> caseLocationOptions    = buildCaseLocationOptions();

            responseMap.put('status', 'success');
            responseMap.put('message', 'Picklist options fetched successfully');
            responseMap.put('visitTypeOptions', visitTypeOptions);
            // responseMap.put('supportTypeOptions', supportTypeOptions);
            // responseMap.put('supportSubTypeOptions', supportSubTypeOptions);
            responseMap.put('caseLocationOptions', caseLocationOptions);
            responseMap.put('referAndEarnFilterOptions', referAndEarnFilterOptions);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serializePretty(responseMap));
        } catch (Exception ex) {
            System.debug('Error in API_PicklistValues.getPicklistValues ===> ' + ex.getMessage() + ' | line ' + ex.getLineNumber());
            IntegrationLogUtility.captureError('API_PicklistValues', 'getPicklistValues', ex, null, 'SFA - SFDC');
            responseMap.put('status', 'error');
            responseMap.put('message', 'Internal Server Error');
            responseMap.put('referAndEarnFilterOptions', new List<Utility.PicklistOption>());
            responseMap.put('budgetAlignedOptions', new List<Utility.PicklistOption>());
            responseMap.put('supportTypeOptions', new List<Utility.PicklistOption>());
            responseMap.put('supportSubTypeOptions', new List<Utility.PicklistOption>());
            responseMap.put('caseLocationOptions', new List<LocationOptionWrapper>());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serializePretty(responseMap));
        }
    }

    private static List<LocationOptionWrapper> buildCaseLocationOptions() {
        Schema.SObjectField locationField       = Case.Location__c;
        Schema.SObjectField masterCategoryField = Case.Master_Category__c;

        List<Schema.PicklistEntry> locationEntries = locationField.getDescribe().getPicklistValues();
        List<String> activeLocationValues = new List<String>();
        for (Schema.PicklistEntry entry : locationEntries) {
            if (entry.isActive()) {
                activeLocationValues.add(entry.getValue());
            }
        }

        Map<String, List<String>> masterCategoriesByLocation = new Map<String, List<String>>();
        for (String locationValue : activeLocationValues) {
            masterCategoriesByLocation.put(locationValue, new List<String>());
        }

        List<Schema.PicklistEntry> masterCategoryEntries = masterCategoryField.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry dependentEntry : masterCategoryEntries) {
            if (!dependentEntry.isActive()) {
                continue;
            }

            Map<String, Object> dependentEntryMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dependentEntry));
            String validForBase64 = (String) dependentEntryMap.get('validFor');
            if (String.isBlank(validForBase64)) {
                continue;
            }

            for (Integer validIndex : decodeValidForIndexes(validForBase64)) {
                if (validIndex < 0 || validIndex >= activeLocationValues.size()) {
                    continue;
                }
                String locationValue = activeLocationValues[validIndex];
                List<String> masterCategoryValues = masterCategoriesByLocation.get(locationValue);
                if (!masterCategoryValues.contains(dependentEntry.getValue())) {
                    masterCategoryValues.add(dependentEntry.getValue());
                }
            }
        }

        Map<String, List<SubCategoryOptionWrapper>> subCategoriesByCombinationKey = buildSubCategoriesByCombinationKey();

        List<LocationOptionWrapper> caseLocationOptions = new List<LocationOptionWrapper>();
        for (String locationValue : activeLocationValues) {
            LocationOptionWrapper locationOption = new LocationOptionWrapper();
            locationOption.label = locationValue;
            locationOption.value = locationValue;
            locationOption.masterCategories = new List<MasterCategoryOptionWrapper>();

            for (String masterCategoryValue : masterCategoriesByLocation.get(locationValue)) {
                MasterCategoryOptionWrapper masterCategoryOption = new MasterCategoryOptionWrapper();
                masterCategoryOption.label = masterCategoryValue;
                masterCategoryOption.value = masterCategoryValue;

                String combinationKey = buildCombinationKey(locationValue, masterCategoryValue);
                List<SubCategoryOptionWrapper> subCategories = subCategoriesByCombinationKey.get(combinationKey);
                masterCategoryOption.subCategories = subCategories != null ? subCategories : new List<SubCategoryOptionWrapper>();

                locationOption.masterCategories.add(masterCategoryOption);
            }

            caseLocationOptions.add(locationOption);
        }

        return caseLocationOptions;
    }

    private static Map<String, List<SubCategoryOptionWrapper>> buildSubCategoriesByCombinationKey() {
        Map<String, List<SubCategoryOptionWrapper>> subCategoriesByCombinationKey = new Map<String, List<SubCategoryOptionWrapper>>();

        for (Case_Sub_Category_Option__mdt metadataRecord : [SELECT MasterLabel, Location_Category_Combination__c, Sub_category__c FROM Case_Sub_Category_Option__mdt WITH System_Mode]) {
            String combination = metadataRecord.Location_Category_Combination__c;
            if (String.isBlank(combination)) {
                continue;
            }

            Integer separatorIndex = combination.indexOf('-');
            if (separatorIndex <= 0 || separatorIndex == combination.length() - 1) {
                continue;
            }

            String locationPart       = combination.substring(0, separatorIndex).trim();
            String masterCategoryPart = combination.substring(separatorIndex + 1).trim();
            if (String.isBlank(locationPart) || String.isBlank(masterCategoryPart)) {
                continue;
            }

            String combinationKey = buildCombinationKey(locationPart, masterCategoryPart);

            List<SubCategoryOptionWrapper> subCategories = subCategoriesByCombinationKey.containsKey(combinationKey)? subCategoriesByCombinationKey.get(combinationKey): new List<SubCategoryOptionWrapper>();

            Set<String> seenSubCategoryValues = new Set<String>();
            for (SubCategoryOptionWrapper existing : subCategories) {
                seenSubCategoryValues.add(existing.value);
            }

            if (String.isNotBlank(metadataRecord.Sub_category__c)) {
                for (String rawSubCategory : metadataRecord.Sub_category__c.split(',')) {
                    String subCategoryValue = rawSubCategory.trim();
                    if (String.isBlank(subCategoryValue) || seenSubCategoryValues.contains(subCategoryValue)) {
                        continue;
                    }
                    SubCategoryOptionWrapper subCategoryOption = new SubCategoryOptionWrapper();
                    subCategoryOption.label = subCategoryValue;
                    subCategoryOption.value = subCategoryValue;
                    subCategories.add(subCategoryOption);
                    seenSubCategoryValues.add(subCategoryValue);
                }
            }

            subCategoriesByCombinationKey.put(combinationKey, subCategories);
        }

        return subCategoriesByCombinationKey;
    }

    private static String buildCombinationKey(String locationValue, String masterCategoryValue) {
        return locationValue + '-' + masterCategoryValue;
    }

    private static List<Integer> decodeValidForIndexes(String validForBase64) {
        List<Integer> validIndexes = new List<Integer>();
        String hexString = EncodingUtil.convertToHex(EncodingUtil.base64Decode(validForBase64));
        String hexDigits = '0123456789abcdef';

        Integer bitPosition = 0;
        for (Integer charIndex = 0; charIndex < hexString.length(); charIndex += 2) {
            Integer byteValue = hexDigits.indexOf(hexString.substring(charIndex, charIndex + 1)) * 16
                            + hexDigits.indexOf(hexString.substring(charIndex + 1, charIndex + 2));
            for (Integer bit = 7; bit >= 0; bit--) {
                if ((byteValue & (1 << bit)) != 0) {
                    validIndexes.add(bitPosition);
                }
                bitPosition++;
            }
        }
        return validIndexes;
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

    public class LocationOptionWrapper {
        public String label;
        public String value;
        public List<MasterCategoryOptionWrapper> masterCategories;
    }

    public class MasterCategoryOptionWrapper {
        public String label;
        public String value;
        public List<SubCategoryOptionWrapper> subCategories;
    }

    public class SubCategoryOptionWrapper {
        public String label;
        public String value;
    }
}