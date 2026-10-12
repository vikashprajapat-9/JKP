import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LOGO_WHITE from '@salesforce/resourceUrl/Logo_White';
import getCaseData from '@salesforce/apex/DOANewBuyerController.getCaseData';
import saveBuyerDetailsAndCloseTask from '@salesforce/apex/DOANewBuyerController.saveBuyerDetailsAndCloseTask';

export default class DoaNewBuyerDetails extends LightningElement {
    @api recordId; // Receives Task ID or Case ID
    logoWhite = LOGO_WHITE;
    pageTitle = 'Capture New Buyer Details (Deed of Assignment)';

    @track buyerName = '';
    @track buyerEmail = '';
    @track buyerPhone = '';
    @track address = '';
    @track nic = '';
    @track isDualCitizen = false;
    @track hasPOA = false;
    @track settlementType = '';
    @track pendingAmount = 0;
    @track interestAmount = 0;

    isLoading = false;
    isSaving = false;

    settlementOptions = [
        { label: 'Before DOA', value: 'Before DOA' },
        { label: 'On Date DOA', value: 'On Date DOA' }
    ];

    connectedCallback() {
        console.log('Record ID received in LWC ==> ', this.recordId);
        if (this.recordId) {
            this.loadExistingData();
        }
    }

    // Load initial values from Case
    async loadExistingData() {
        this.isLoading = true;
        try {
            const data = await getCaseData({ recordId: this.recordId });
            console.log('Existing Case Data Loaded ==> ', JSON.stringify(data));
            if (data) {
                this.buyerName = data.Name__c || '';
                this.buyerEmail = data.Email__c || '';
                this.buyerPhone = data.Phone__c || '';
                this.address = data.Address__c || '';
                this.nic = data.National_Identity_Card__c || '';
                this.isDualCitizen = data.Is_Dual_Citizen__c || false;
                this.hasPOA = data.Has_Power_of_Attorney__c || false;
                this.settlementType = data.Amount_Settlement_Type__c || '';
                this.pendingAmount = data.Pending_Amount__c || 0;
                this.interestAmount = data.Interest_Amount__c || 0;
            }
        } catch (error) {
            console.error('Error loading Case data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    // Input handlers
    handleNameChange(e) { this.buyerName = e.target.value; }
    handleEmailChange(e) { this.buyerEmail = e.target.value; }
    handlePhoneChange(e) { this.buyerPhone = e.target.value; }
    handleNicChange(e) { this.nic = e.target.value; }
    handleAddressChange(e) { this.address = e.target.value; }
    handleDualCitizenChange(e) { this.isDualCitizen = e.target.checked; }
    handlePOAChange(e) { this.hasPOA = e.target.checked; }
    handleSettlementChange(e) { this.settlementType = e.detail.value; }
    handlePendingAmountChange(e) { this.pendingAmount = Number(e.target.value) || 0; }
    handleInterestAmountChange(e) { this.interestAmount = Number(e.target.value) || 0; }

    // Form Validation
    validateForm() {
        let isValid = true;
        const inputFields = this.template.querySelectorAll('lightning-input, lightning-textarea, lightning-combobox');
        inputFields.forEach(field => {
            if (!field.checkValidity()) {
                field.reportValidity();
                isValid = false;
            }
        });
        return isValid;
    }

    // Submit Handler
    async handleSubmit() {
        if (!this.validateForm()) {
            this.showToast('Validation Error', 'Please complete all required fields.', 'error');
            return;
        }

        this.isSaving = true;

        const casePayload = {
            sobjectType: 'Case',
            Name__c: this.buyerName,
            Email__c: this.buyerEmail,
            Phone__c: this.buyerPhone,
            Address__c: this.address,
            National_Identity_Card__c: this.nic,
            Is_Dual_Citizen__c: this.isDualCitizen,
            Has_Power_of_Attorney__c: this.hasPOA,
            Amount_Settlement_Type__c: this.settlementType,
            Pending_Amount__c: this.pendingAmount,
            Interest_Amount__c: this.interestAmount
        };

        console.log('Submitting Payload ==> ', JSON.stringify(casePayload));

        try {
            const result = await saveBuyerDetailsAndCloseTask({
                recordId: this.recordId,
                caseData: casePayload
            });

            console.log('Result from Apex ==> ', result);

            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);

            this.showToast('Success', 'New Buyer details saved & Verification Task completed!', 'success');
            
            // Close the modal
            this.handleCancel();

        } catch (error) {
            console.error('Save Error:', error);
            this.showToast('Error', error?.body?.message || error?.message || 'Error saving details.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Handles modal closing in all scenarios (Quick Action, Custom Modal, Event)
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
        this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}