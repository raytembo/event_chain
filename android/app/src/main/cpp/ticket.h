// ticket.h - EventTicket struct
#ifndef TICKET_H
#define TICKET_H
#include <string>
#include <sstream>
#include <vector>
#include <iomanip>
#include <stdexcept>
struct EventTicket
{
    std::string ticketID;
    std::string eventName;
    std::string eventDate;
    std::string venue;
    std::string ownerName;
    std::string ownerID;
    std::string ticketType;
    double      price;
    std::string serialize() const
    {
        std::ostringstream oss;
        oss << ticketID << "|" << eventName << "|" << eventDate << "|"
            << venue << "|" << ownerName << "|" << ownerID << "|"
            << ticketType << "|" << std::fixed << std::setprecision(2) << price;
        return oss.str();
    }
    static EventTicket deserialize(const std::string& raw)
    {
        EventTicket t;
        std::istringstream iss(raw);
        std::vector<std::string> parts;
        std::string token;
        while (std::getline(iss, token, '|'))
            parts.push_back(token);
        if (parts.size() < 8)
            throw std::runtime_error("Corrupted ticket data.");
        t.ticketID=parts[0]; t.eventName=parts[1]; t.eventDate=parts[2];
        t.venue=parts[3]; t.ownerName=parts[4]; t.ownerID=parts[5];
        t.ticketType=parts[6]; t.price=std::stod(parts[7]);
        return t;
    }
};
#endif // TICKET_H
