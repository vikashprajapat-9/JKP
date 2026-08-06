import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import searchRecords from '@salesforce/apex/SiteVisitController.searchRecords';
import createVisit from '@salesforce/apex/SiteVisitController.createVisit';

export default class SiteVisitPortal extends LightningElement {
    searchKey = '';
    @track leads = [];
    @track opportunities = [];
    showResults = false;
    showNoRecords = false;
    isLoading = false;
    showVisitModal = false;
    selectedLeadId;
    selectedOpportunityId;
    visit = {};
    requirementOptions = [
        { label: 'Residential', value: 'Residential' },
        { label: 'Commercial', value: 'Commercial' }
    ];
    projectOptions = [
        { label: 'Project A', value: 'Project A' },
        { label: 'Project B', value: 'Project B' }
    ];

    //===================================
    // Search Box
    //===================================

    handleSearchChange(event){
        this.searchKey = event.target.value;
    }

    //===================================
    // Search Records
    //===================================

    async searchRecords(){
        if(!this.searchKey){
            this.showToast(
                'Error',
                'Please enter Email or Phone.',
                'error'
            );
            return;
        }
        this.isLoading = true;
        try{
            const result = await searchRecords({
                searchKey : this.searchKey
            });
            this.leads = result.leads || [];
            this.opportunities = result.opportunities || [];
            this.showResults = true;
            this.showNoRecords =
                this.leads.length===0 &&
                this.opportunities.length===0;
        }
        catch(error){
            console.error(error);
            this.showToast(
                'Error',
                'Unable to search records.',
                'error'
            );
        }
        finally{
            this.isLoading = false;
        }
    }

    //===================================
    // Open Modal
    //===================================

    openVisitModal(event){
        this.selectedLeadId = null;
        this.selectedOpportunityId = null;
        const id = event.currentTarget.dataset.id;
        const type = event.currentTarget.dataset.type;
        if(type === 'Lead'){
            this.selectedLeadId = id;
        }
        else{
            this.selectedOpportunityId = id;
        }
        this.visit = {};
        this.showVisitModal = true;
    }

    //===================================
    // Close Modal
    //===================================

    closeVisitModal(){
        this.showVisitModal = false;
    }

    //===================================
    // Visit Input
    //===================================

    handleVisitChange(event){
        const field = event.target.name;
        this.visit[field] = event.detail.value;
    }

    //===================================
    // Save Visit
    //===================================

    async saveVisit(){
        this.isLoading = true;
        try{
            const visitRecord = {
                Actual_Visit_Date__c:
                    this.visit.Actual_Visit_Date__c,
                Remarks__c:
                    this.visit.Remarks__c,
                Requirement_Type__c:
                    this.visit.Requirement_Type__c,
                Project_Name__c:
                    this.visit.Project_Name__c
            };
            await createVisit({
                leadId : this.selectedLeadId,
                opportunityId : this.selectedOpportunityId,
                visit : visitRecord
            });
            this.showToast(
                'Success',
                'Visit Created Successfully',
                'success'
            );
            this.showVisitModal = false;
            this.visit = {};
        }
        catch(error){
            console.error(error);
            this.showToast(
                'Error',
                error.body.message,
                'error'
            );
        }
        finally{
            this.isLoading = false;
        }
    }

    //===================================
    // Toast
    //===================================
    
    showToast(title,message,variant){
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}