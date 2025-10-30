// token.move (updated: added public mint function)
module PROTO::token {
    use std::signer;
    use std::string::{Self, String};
    use std::option;

    use supra_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use supra_framework::object::{Self, Object};
    use supra_framework::primary_fungible_store;

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_TOKEN_ALREADY_INITIALIZED: u64 = 2;

    /// Token configuration
    const TOKEN_NAME: vector<u8> = b"PROTO Token";
    const TOKEN_SYMBOL: vector<u8> = b"PROTO";
    const TOKEN_DECIMALS: u8 = 8;
    const TOKEN_ICON_URI: vector<u8> = b"https://proto.com/icon.png";
    const TOKEN_PROJECT_URI: vector<u8> = b"https://proto.com";

    /// Token metadata storage
    struct TokenRefs has key {
        mint_ref: fungible_asset::MintRef,
        burn_ref: fungible_asset::BurnRef,
        transfer_ref: fungible_asset::TransferRef,
        metadata: Object<Metadata>,
    }

    /// Initialize the token (called once by admin)
    public entry fun initialize_token(admin: &signer, max_supply: u64) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);
        assert!(!exists<TokenRefs>(@PROTO), E_TOKEN_ALREADY_INITIALIZED);

        // Create the fungible asset
        let constructor_ref = object::create_named_object(admin, TOKEN_NAME);
        
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::some((max_supply as u128)),  // max supply
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            TOKEN_DECIMALS,
            string::utf8(TOKEN_ICON_URI),
            string::utf8(TOKEN_PROJECT_URI),
        );

        // Generate refs for minting, burning, and transfers
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        // Store refs for future use
        move_to(admin, TokenRefs {
            mint_ref,
            burn_ref,
            transfer_ref,
            metadata,
        });
    }

    /// Mint tokens (internal, called by airdrop)
    fun mint(amount: u64): FungibleAsset acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        fungible_asset::mint(&token_refs.mint_ref, amount)
    }

    /// Mint tokens to a specific address (admin only)
    public entry fun mint_to(admin: &signer, to: address, amount: u64) acquires TokenRefs {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);

        let token_refs = borrow_global<TokenRefs>(@PROTO);
        let fa = fungible_asset::mint(&token_refs.mint_ref, amount);
        primary_fungible_store::deposit(to, fa);
    }

    /// Burn tokens from admin's account
    public entry fun burn(admin: &signer, amount: u64) acquires TokenRefs {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @PROTO, E_NOT_ADMIN);

        let token_refs = borrow_global<TokenRefs>(@PROTO);
        let fa = primary_fungible_store::withdraw(admin, token_refs.metadata, amount);
        fungible_asset::burn(&token_refs.burn_ref, fa);
    }

    // ======================
    // VIEW FUNCTIONS
    // ======================

    // Get token metadata object
    #[view]
    public fun get_metadata(): Object<Metadata> acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        token_refs.metadata
    }

    // Check if token is initialized
    #[view]
    public fun is_initialized(): bool {
        exists<TokenRefs>(@PROTO)
    }

    // Get token info
    #[view] 
    public fun get_token_info(): (String, String, u8) acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        let metadata = token_refs.metadata;
        (
            fungible_asset::name(metadata),
            fungible_asset::symbol(metadata), 
            fungible_asset::decimals(metadata)
        )
    }

    // Get total supply
    #[view]
    public fun get_total_supply(): option::Option<u128> acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        fungible_asset::supply(token_refs.metadata)
    }

    // Get max supply
    #[view]
    public fun get_max_supply(): option::Option<u128> acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        fungible_asset::maximum(token_refs.metadata)
    }

    // Get balance of an address
    #[view]
    public fun get_balance(addr: address): u64 acquires TokenRefs {
        let token_refs = borrow_global<TokenRefs>(@PROTO);
        primary_fungible_store::balance(addr, token_refs.metadata)
    }
}