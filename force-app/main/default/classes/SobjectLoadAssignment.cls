public class SobjectLoadAssignment {
    Public Static Map<String,Id> rv_MapOfQueueNameByQueueID = new Map<String,Id>();
    Public Static Map<Id,List<Assignment_Group_Member__c>> rv_MapOfAGIDByASMList = new Map<Id,List<Assignment_Group_Member__c>>();
    Public Static Map<Id,Assignment_Group_Member__c> rv_MapOfAGMIDByAGM = new Map<Id,Assignment_Group_Member__c>();
    Public Static Map<Id,Assignment_Group__c> rv_MapOfAGIdByAG = new Map<Id,Assignment_Group__c>();
    Public Static Map<Id,Map<Integer,Id>> rv_MapofAGIdByAGMRRIDByAGMId = new Map<Id,Map<Integer,Id>>();
    
    Public Static void ExecuteLoadAssignment(Integer limitSize){
        rv_MapOfQueueNameByQueueID = SobjectLoadAssignmentUtility.GetQueuesNameAndId();
        system.debug('rv_MapOfQueueNameByQueueID::>>' + rv_MapOfQueueNameByQueueID);
        rv_MapOfAGIdByAG = SobjectLoadAssignmentUtility.GetassigmentGroup();
        System.debug('rv_MapOfAGIdByAG::>>' + rv_MapOfAGIdByAG);
        GetAssignMentGroupMemberAndAssignmentGroup();
        for(Assignment_Group__c rv_AGRec : rv_MapOfAGIdByAG.values()){
            if(rv_AGRec.Execution_SOQL__c != null){
                if(limitSize > 0){
                    rv_AGRec.Execution_SOQL__c += ' LIMIT ' + limitSize;
                }
                ExecuteSobjectAssignment(rv_AGRec.Execution_SOQL__c,rv_AGRec.Id,rv_MapOfQueueNameByQueueID.get(rv_AGRec.Round_Robin_Queue_Name__c));
            }
        }
    }
    
    Public static void GetAssignMentGroupMemberAndAssignmentGroup(){
        List<Assignment_Group__c> rv_AssignmentGroup = New List<Assignment_Group__c>();
        List<Assignment_Group_Member__c> rv_AssignmentGroupMember = New List<Assignment_Group_Member__c>();
        
        // rv_AssignmentGroupMember = [SELECT Id,Assignment_Group__c,Last_Allocated_RRID__c,Max_Case_Per_Day__c,Out_Of_Office__c,Group_Member__c,Max_Sobject_Assignment_Count__c,
        //                             Assignment_Id__c,Assignment_Group__r.Name,Assignment_Group__r.Case_Stage_Exceed_Count__c,Assignment_Group__r.Case_Stage__c,
        //                             Assignment_Group__r.Execution_SOQL__c,Assignment_Group__r.isActive__c,Assignment_Group__r.Last_Allocated_RRid__c,
        //                             Assignment_Group__r.Minimum_Case_Volume__c,Assignment_Group__r.Max_Sobject_Assignment_Count__c,Assignment_Group__r.Round_Robin_Queue_Name__c,LastModifiedDate,Active__c,BreakTime_Started__c
        //                             From Assignment_Group_Member__c 
        //                             WHERE Assignment_Group__r.isActive__c = true  and 
        //                             Out_Of_Office__c = false and BreakTime_Started__c = false ORDER BY Assignment_Id__c];

        rv_AssignmentGroupMember = [SELECT Id,Assignment_Group__c,Last_Allocated_RRID__c,Out_Of_Office__c,Group_Member__c,Max_Sobject_Assignment_Count__c,
                                    Assignment_Id__c,Assignment_Group__r.Name,
                                    Assignment_Group__r.Execution_SOQL__c,Assignment_Group__r.isActive__c,Assignment_Group__r.Last_Allocated_RRid__c,
                                    Assignment_Group__r.Max_Sobject_Assignment_Count__c,Assignment_Group__r.Round_Robin_Queue_Name__c,LastModifiedDate,Active__c,BreakTime_Started__c
                                    From Assignment_Group_Member__c 
                                    WHERE Assignment_Group__r.isActive__c = true  and 
                                    Out_Of_Office__c = false and BreakTime_Started__c = false ORDER BY Assignment_Id__c];
        
        if(!rv_AssignmentGroupMember.isEmpty()){
            system.debug('rv_AssignmentGroupMember::>>' + rv_AssignmentGroupMember);
            for(Assignment_Group_Member__c agmRec : rv_AssignmentGroupMember){
                rv_MapOfAGMIDByAGM.put(agmRec.Id,agmRec);
                if(rv_MapOfAGIDByASMList.containsKey(agmRec.Assignment_Group__c)){
                    rv_MapOfAGIDByASMList.get(agmRec.Assignment_Group__c).add(agmRec);
                }else{
                    rv_MapOfAGIDByASMList.put(agmRec.Assignment_Group__c,new list<Assignment_Group_Member__c>{agmRec});
                } 
                if(rv_MapofAGIdByAGMRRIDByAGMId.containsKey(agmRec.Assignment_Group__c)){
                    Map<Integer,Id> tempMap = new MAp<Integer,Id>();
                    tempMap = rv_MapofAGIdByAGMRRIDByAGMId.get(agmRec.Assignment_Group__c);
                    tempMap.put(Integer.valueOf(agmRec.Assignment_Id__c),agmRec.Id);
                    rv_MapofAGIdByAGMRRIDByAGMId.put(agmRec.Assignment_Group__c,tempMap);
                }else{
                    rv_MapofAGIdByAGMRRIDByAGMId.put(agmRec.Assignment_Group__c,new Map<Integer,Id> {Integer.valueOf(agmRec.Assignment_Id__c)=>agmRec.Group_Member__c});
                }
            }
        }
    }
    
    
    Public static void ExecuteSobjectAssignment(String databaseQuery,String GroupId,Id queueId){
        system.debug('entered into future method::>>');
        List<sObject> rv_SobjectRecDetails = Database.query(databaseQuery);
        System.debug('rv_SobjectRecDetails::>>' + rv_SobjectRecDetails);
        SobjectLoadAssignmentHelper.ExecuteSobjectOwnerAssignment(rv_SobjectRecDetails, GroupId, queueId);
    }
}