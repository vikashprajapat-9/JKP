@RestResource(urlMapping='/api/v1/support-type-options/*')
global without sharing class API_SupportTypeOptions {

    private static final String DLP_ISSUE = 'dlp issue';

    private static final Set<String> ALWAYS_EXCLUDED = new Set<String>{'deed of cancellation','sale order cancellation'};

    @HttpGet
    global static void getSupportTypeOptions() {
        RestRequest request   = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            Map<String, String> params = request != null && request.params != null ? request.params : new Map<String, String>();
            String unitId = params.get('unitId');

            Boolean dlpActive = false;
            if (String.isNotBlank(unitId) && isValidSalesforceId(unitId.trim())) {
                dlpActive = isDlpActiveForUnit(unitId.trim());
            }

            List<OptionWrapper> options = getPicklistOptions(Case.Type, dlpActive);

            Map<String, Object> responseMap = new Map<String, Object>();
            responseMap.put('status', 'success');
            responseMap.put('message', 'Support type options fetched successfully');
            responseMap.put('supportTypeOptions', options);

            response.statusCode   = 200;
            response.responseBody = Blob.valueOf(JSON.serializePretty(responseMap));
        } catch (Exception e) {
            System.debug('Error in API_SupportTypeOptions.getSupportTypeOptions ===> ' + e.getMessage() + ' | line ' + e.getLineNumber());
            IntegrationLogUtility.captureError('API_SupportTypeOptions', 'getSupportTypeOptions', e, null, 'SFA - SFDC');

            Map<String, Object> errorMap = new Map<String, Object>();
            errorMap.put('status', 'error');
            errorMap.put('message', 'Internal Server Error');
            errorMap.put('supportTypeOptions', new List<OptionWrapper>());

            response.statusCode   = 500;
            response.responseBody = Blob.valueOf(JSON.serializePretty(errorMap));
        }
    }

    private static Boolean isDlpActiveForUnit(String unitId) {
        Date today = Date.today();
        for (Opportunity opportunity : [SELECT Id, DLP_Start_Date__c, DLP_End_Date__c FROM Opportunity WHERE Unit__c = :unitId WITH SYSTEM_MODE]) {
            if (opportunity.DLP_Start_Date__c == null || opportunity.DLP_End_Date__c == null) {
                continue;
            }
            if (today >= opportunity.DLP_Start_Date__c && today <= opportunity.DLP_End_Date__c) {
                return true;
            }
        }
        return false;
    }

    private static List<OptionWrapper> getPicklistOptions(Schema.SObjectField field, Boolean dlpActive) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }

            String value = entry.getValue().toLowerCase();
            String label = entry.getLabel().toLowerCase();

            if (ALWAYS_EXCLUDED.contains(value) || ALWAYS_EXCLUDED.contains(label)) {
                continue;
            }
            if (!dlpActive && (value == DLP_ISSUE || label == DLP_ISSUE)) {
                continue;
            }

            OptionWrapper option = new OptionWrapper();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    private static Boolean isValidSalesforceId(String recordId) {
        try {
            Id.valueOf(recordId);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public class OptionWrapper {
        public String label;
        public String value;
    }
}