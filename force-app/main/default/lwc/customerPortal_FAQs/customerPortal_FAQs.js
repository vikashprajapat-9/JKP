import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFAQs from '@salesforce/apex/CustomerPortalController.getFAQs';
import CP_ASSETS from '@salesforce/resourceUrl/customerPortalAssets';

const DEFAULT_CATEGORY_KEY = 'billing';
const LOADING_TEXT = 'Loading FAQs';
const ERROR_TEXT = "We couldn't load FAQs right now. Please try again in a moment.";
const EMPTY_TEXT = 'No FAQs available for this category.';
const TABS_LABEL = 'FAQ categories';
const TOAST_ERROR_TITLE = 'Error';
const TOAST_ERROR_MESSAGE = 'Unable to load FAQs. Please try again.';

export default class CustomerPortal_FAQs extends LightningElement {

    pageData;
    isLoading = true;
    hasError = false;

    activeCategoryKey = DEFAULT_CATEGORY_KEY;
    openFaqId = null;

    loadingText = LOADING_TEXT;
    errorText = ERROR_TEXT;
    emptyText = EMPTY_TEXT;
    tabsLabel = TABS_LABEL;
    emptyImg = CP_ASSETS + '/empty-state.svg';

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
            this.showErrorToast(TOAST_ERROR_MESSAGE);
        } finally {
            this.isLoading = false;
        }
    }

    showErrorToast(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: TOAST_ERROR_TITLE,
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

    get rawCategories() {
        return this.pageData && Array.isArray(this.pageData.categories) ? this.pageData.categories : [];
    }

    // the selected tab; falls back to the first category when the default key is not in the data
    get currentCategoryKey() {
        const categories = this.rawCategories;
        if (categories.some((c) => c.key === this.activeCategoryKey)) {
            return this.activeCategoryKey;
        }
        return categories.length ? categories[0].key : null;
    }

    get categories() {
        const currentKey = this.currentCategoryKey;
        return this.rawCategories.map((cat) => {
            const isActive = cat.key === currentKey;
            return {
                key: cat.key,
                label: cat.label,
                ariaSelected: isActive ? 'true' : 'false',
                tabClass: isActive ? 'cp-tab cp-tab_active' : 'cp-tab'
            };
        });
    }

    get activeCategoryRaw() {
        const currentKey = this.currentCategoryKey;
        return this.rawCategories.find((c) => c.key === currentKey) || null;
    }

    get activeCategoryLabel() {
        const category = this.activeCategoryRaw;
        return category ? category.label : '';
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
                    ariaExpanded: isOpen ? 'true' : 'false',
                    chevronClass: isOpen ? 'faq-chevron faq-chevron_open' : 'faq-chevron'
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