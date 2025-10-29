// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title SimpleEventTicketing
/// @author
/// @notice Beginner contract for decentralized event ticketing with proof-of-purchase
contract SimpleEventTicketing {
    uint256 private nextEventId = 1;
    uint256 private nextTicketId = 1;

    struct Event {
        uint256 id;
        string name;
        uint256 datetime; // unix timestamp
        address payable organizer;
        uint256 price; // price per ticket in wei
        uint256 totalTickets;
        uint256 ticketsSold;
        bool canceled;
    }

    struct Ticket {
        uint256 id;
        uint256 eventId;
        address owner;
        bool valid;
    }

    // eventId => Event
    mapping(uint256 => Event) public events;

    // ticketId => Ticket
    mapping(uint256 => Ticket) public tickets;

    // eventId => balance (accumulated funds from ticket sales)
    mapping(uint256 => uint256) public eventBalances;

    // Organizer can create events
    event EventCreated(uint256 indexed eventId, string name, address indexed organizer, uint256 price, uint256 totalTickets);
    event EventCanceled(uint256 indexed eventId);

    // Emitted when a ticket is purchased. receiptHash serves as a compact proof-of-purchase.
    // Keep the receiptHash off-chain to verify purchase later if needed.
    event Purchase(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer, bytes32 receiptHash);

    event TicketTransferred(uint256 indexed ticketId, address indexed from, address indexed to);
    event Withdrawn(uint256 indexed eventId, address indexed organizer, uint256 amount);

    modifier onlyOrganizer(uint256 eventId) {
        require(events[eventId].organizer == msg.sender, "not organizer");
        _;
    }

    modifier eventExists(uint256 eventId) {
        require(events[eventId].id != 0, "event does not exist");
        _;
    }

    /// @notice Create a new event
    /// @param name Event name
    /// @param datetime Unix timestamp for the event (informational)
    /// @param price Price per ticket (in wei)
    /// @param totalTickets Total tickets available
    function createEvent(
        string calldata name,
        uint256 datetime,
        uint256 price,
        uint256 totalTickets
    ) external returns (uint256) {
        require(totalTickets > 0, "totalTickets > 0");

        uint256 eventId = nextEventId++;
        events[eventId] = Event({
            id: eventId,
            name: name,
            datetime: datetime,
            organizer: payable(msg.sender),
            price: price,
            totalTickets: totalTickets,
            ticketsSold: 0,
            canceled: false
        });

        emit EventCreated(eventId, name, msg.sender, price, totalTickets);
        return eventId;
    }

    /// @notice Buy one ticket for an event. Payment must equal event price.
    /// @param eventId ID of the event
    function buyTicket(uint256 eventId) external payable eventExists(eventId) {
        Event storage ev = events[eventId];
        require(!ev.canceled, "event canceled");
        require(ev.ticketsSold < ev.totalTickets, "sold out");
        require(msg.value == ev.price, "incorrect payment");

        uint256 ticketId = nextTicketId++;
        tickets[ticketId] = Ticket({
            id: ticketId,
            eventId: eventId,
            owner: msg.sender,
            valid: true
        });

        ev.ticketsSold += 1;
        eventBalances[eventId] += msg.value;

        // Create a receipt hash that can be used as proof-of-purchase
        // Note: block.timestamp is included to make receipt unique; store receipt off-chain if you want persistence
        bytes32 receiptHash = keccak256(abi.encodePacked(ticketId, msg.sender, eventId, block.timestamp));
        emit Purchase(eventId, ticketId, msg.sender, receiptHash);
    }

    /// @notice Transfer a ticket to another address (simple on-chain transfer)
    /// @param ticketId The ticket to transfer
    /// @param to Recipient address
    function transferTicket(uint256 ticketId, address to) external {
        require(ticketId > 0 && tickets[ticketId].id != 0, "ticket not found");
        Ticket storage t = tickets[ticketId];
        require(t.valid, "ticket not valid");
        require(t.owner == msg.sender, "not ticket owner");
        require(to != address(0), "invalid recipient");

        address from = t.owner;
        t.owner = to;

        emit TicketTransferred(ticketId, from, to);
    }

    /// @notice Organizer withdraws funds collected for their event
    /// @param eventId event to withdraw from
    function withdrawFunds(uint256 eventId) external eventExists(eventId) onlyOrganizer(eventId) {
        uint256 amount = eventBalances[eventId];
        require(amount > 0, "no funds");

        eventBalances[eventId] = 0; // pull pattern: zero first
        (bool sent, ) = events[eventId].organizer.call{value: amount}("");
        require(sent, "withdraw failed");
        emit Withdrawn(eventId, events[eventId].organizer, amount);
    }

    /// @notice Cancel an event. Organizer can cancel and mark event canceled. Buyers would need separate refund logic to claim — not implemented here (keeps example simple).
    /// @param eventId id of event to cancel
    function cancelEvent(uint256 eventId) external eventExists(eventId) onlyOrganizer(eventId) {
        events[eventId].canceled = true;
        emit EventCanceled(eventId);
    }

    // --- View helpers ---

    /// @notice Get ticket details
    function getTicket(uint256 ticketId) external view returns (uint256, uint256, address, bool) {
        Ticket storage t = tickets[ticketId];
        require(t.id != 0, "ticket not found");
        return (t.id, t.eventId, t.owner, t.valid);
    }

    /// @notice Quick verify helper: is ticket owned by `who` and valid?
    function verifyTicketOwner(uint256 ticketId, address who) external view returns (bool) {
        Ticket storage t = tickets[ticketId];
        if (t.id == 0) return false;
        return (t.owner == who && t.valid);
    }

    /// @notice Get event summary
    function getEvent(uint256 eventId) external view eventExists(eventId) returns (
        uint256 id,
        string memory name,
        uint256 datetime,
        address organizer,
        uint256 price,
        uint256 totalTickets,
        uint256 ticketsSold,
        bool canceled
    ) {
        Event storage ev = events[eventId];
        return (ev.id, ev.name, ev.datetime, ev.organizer, ev.price, ev.totalTickets, ev.ticketsSold, ev.canceled);
    }
}
