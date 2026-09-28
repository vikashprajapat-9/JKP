import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFAQs from '@salesforce/apex/customerPortalController.getFAQs';

export default class CustomerPortal_FAQs extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    activeCategoryKey = 'billing';
    openFaqId = null;

    connectedCallback() {
        this.loadFAQs();
    }

    async loadFAQs() {
        this.isLoading = true;
        this.hasError = false;

        try {
            this.pageData = await getFAQs();
        } catch (error) {
            this.hasError = true;
            console.error('customerPortal_FAQs: failed to load FAQs', error);
            this.showErrorToast('Unable to load FAQs. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'dismissable'
            })
        );
    }

    get showContent() {
        return !this.isLoading && !this.hasError && this.pageData;
    }

    get pageTitle() {
        return this.pageData ? this.pageData.title : '';
    }

    get pageDescription() {
        return this.pageData ? this.pageData.description : '';
    }

    get categories() {
        if (!this.pageData || !this.pageData.categories) {
            return [];
        }
        return this.pageData.categories.map((cat) => {
            return {
                key: cat.key,
                label: cat.label,
                tabClass:
                    cat.key === this.activeCategoryKey
                        ? 'tab-btn tab-btn_active'
                        : 'tab-btn'
            };
        });
    }

    get activeCategoryRaw() {
        if (!this.pageData || !this.pageData.categories) {
            return null;
        }
        return this.pageData.categories.find((c) => c.key === this.activeCategoryKey) || null;
    }

    get activeFaqs() {
        const category = this.activeCategoryRaw;
        if (!category || !category.faqs) {
            return [];
        }
        return category.faqs
            .slice()
            .sort((a, b) => (a.displayOrder || 0) - (b.displayOrder || 0))
            .map((faq) => {
                const isOpen = faq.id === this.openFaqId;
                return {
                    ...faq,
                    isOpen,
                    chevronIcon: isOpen ? 'utility:chevronup' : 'utility:chevrondown'
                };
            });
    }

    get hasFaqs() {
        return this.activeFaqs.length > 0;
    }

    handleTabClick(event) {
        const key = event.currentTarget.dataset.key;
        this.activeCategoryKey = key;
        this.openFaqId = null;
    }

    handleFaqToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.openFaqId = this.openFaqId === id ? null : id;
    }
}