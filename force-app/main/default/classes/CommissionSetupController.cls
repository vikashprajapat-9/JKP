// The Apex behind the Commission Setup screens (overview, editor, approval request).
// Each method hands over to a service; the services check what the running user may do.
public without sharing class CommissionSetupController {
    // Messages this class shows or sends
    @TestVisible private static final String COMMISSION_COMMON_ERROR = 'Something went wrong. Please try again.';
    @TestVisible private static final String COMMISSION_SERVICE_NOTHING_TO_SAVE = 'There is nothing to save.';


    public static final String ACTION_DRAFT = 'DRAFT';
    public static final String ACTION_SUBMIT = 'SUBMIT';

    // Parts of a configuration the screens show but a save never reads
    private static final List<String> READ_ONLY_PARTS = new List<String>{ 'baseline', 'siblings', 'approvers' };

    @AuraEnabled
    public static CommissionDto.Workspace getWorkspace() {
        try {
            return CommissionOverviewService.workspace();
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    @AuraEnabled
    public static CommissionDto.Config getConfig(Id configId) {
        try {
            return CommissionConfigService.load(configId);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    // An unsaved draft for a new configuration of the project
    @AuraEnabled
    public static CommissionDto.Config newDraft(Id projectId) {
        try {
            return CommissionConfigService.blank(projectId);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    // An unsaved draft copied from an approved configuration: CORRECTION, CHANGE_FROM_DATE, NEXT_PERIOD, END_EARLY or COPY
    @AuraEnabled
    public static CommissionDto.Config draftFrom(Id sourceId, String choice, Id targetProjectId) {
        try {
            return CommissionConfigService.draftFrom(sourceId, choice, targetProjectId);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    // payload: the configuration as the editor holds it (JSON of CommissionDto.Config). action: DRAFT or SUBMIT.
    @AuraEnabled
    public static CommissionDto.SaveResult saveConfig(String payload, String action) {
        try {
            String wanted = action == null ? ACTION_DRAFT : action.trim().toUpperCase();
            return CommissionConfigService.save(parse(payload), wanted == ACTION_SUBMIT);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    @AuraEnabled
    public static void discardDraft(Id configId) {
        try {
            CommissionConfigService.discard(configId);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    @AuraEnabled
    public static CommissionDto.Config withdraw(Id configId) {
        try {
            return CommissionConfigService.withdraw(configId);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    // decision: APPROVE or REJECT
    @AuraEnabled
    public static CommissionDto.Config decide(Id configId, String decision, String comments) {
        try {
            return CommissionConfigService.decide(configId, decision, comments);
        } catch (Exception problem) {
            throw forScreen(problem);
        }
    }

    // ------------------------------------------------------------ helpers

    // The editor's copy as a CommissionDto.Config. An input the user emptied arrives as "" and would not fit a
    // number, date or id, so empty texts become "no value"; what the screen added for itself is ignored.
    @TestVisible
    private static CommissionDto.Config parse(String payload) {
        if (String.isBlank(payload)) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOTHING_TO_SAVE);
        }
        Object raw = JSON.deserializeUntyped(payload);
        if (!(raw instanceof Map<String, Object>)) {
            throw CommissionDto.error(COMMISSION_SERVICE_NOTHING_TO_SAVE);
        }
        Map<String, Object> body = (Map<String, Object>) raw;
        for (String part : READ_ONLY_PARTS) {
            body.remove(part);
        }
        return (CommissionDto.Config) JSON.deserialize(JSON.serialize(withoutEmptyTexts(body)), CommissionDto.Config.class);
    }

    private static Object withoutEmptyTexts(Object value) {
        if (value instanceof Map<String, Object>) {
            Map<String, Object> entries = (Map<String, Object>) value;
            for (String name : new List<String>(entries.keySet())) {
                entries.put(name, withoutEmptyTexts(entries.get(name)));
            }
            return entries;
        }
        if (value instanceof List<Object>) {
            List<Object> items = (List<Object>) value;
            for (Integer index = 0; index < items.size(); index++) {
                items[index] = withoutEmptyTexts(items[index]);
            }
            return items;
        }
        if (value instanceof String && String.isBlank((String) value)) {
            return null;
        }
        return value;
    }

    // A message a service raised for the user goes through as it is; anything unexpected is shown behind the
    // general "something went wrong" text, with the original message so that support can see the cause.
    private static AuraHandledException forScreen(Exception problem) {
        if (problem instanceof AuraHandledException) {
            return (AuraHandledException) problem;
        }
        return CommissionDto.error(COMMISSION_COMMON_ERROR + ' ' + CommissionConfigService.messageOf(problem));
    }
}