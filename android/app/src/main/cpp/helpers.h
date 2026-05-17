// =============================================================================
//  helpers.h  -  Simple console input helpers
//  Keeps eventchain.cpp clean by moving "ask-and-re-ask" loops here.
// =============================================================================
#ifndef HELPERS_H
#define HELPERS_H

#include <iostream>
#include <string>

// Asks a question and keeps asking until the user gives a non-empty answer.
inline std::string prompt(const std::string& question)
{
    std::string value;
    while (value.empty())
    {
        std::cout << "  " << question;
        std::getline(std::cin, value);
        if (value.empty())
            std::cout << "  (cannot be blank, please try again)\n";
    }
    return value;
}

// Asks for a dollar amount and re-prompts until the input is a valid number.
inline double promptPrice()
{
    while (true)
    {
        std::cout << "  Ticket price ($): ";
        std::string s;
        std::getline(std::cin, s);
        try
        {
            double v = std::stod(s);
            if (v >= 0.0) return v;
        }
        catch (...) {}
        std::cout << "  Please enter a valid number.\n";
    }
}

// Shows four ticket type options and returns the chosen string.
inline std::string promptTicketType()
{
    const char* opts[] = { "VIP", "General", "Backstage", "Student" };
    while (true)
    {
        std::cout << "  Type [1=VIP / 2=General / 3=Backstage / 4=Student]: ";
        std::string s;
        std::getline(std::cin, s);
        try
        {
            int c = std::stoi(s);
            if (c >= 1 && c <= 4) return opts[c - 1];
        }
        catch (...) {}
        std::cout << "  Please enter 1, 2, 3 or 4.\n";
    }
}

#endif // HELPERS_H
