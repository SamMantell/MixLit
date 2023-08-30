#include <Windows.h>
#include <tchar.h>
#include <iostream>
#include <fstream>

int _tmain() {
    HANDLE hSerial = CreateFile(
        _T("COM5"),
        GENERIC_READ,
        0,
        NULL,
        OPEN_EXISTING,
        0,
        NULL
    );

    if (hSerial == INVALID_HANDLE_VALUE) {
        std::cerr << "Failed to open COM port" << std::endl;
        return 1;
    }

    DCB dcbSerialParams = { 0 };
    dcbSerialParams.DCBlength = sizeof(dcbSerialParams);

    if (!GetCommState(hSerial, &dcbSerialParams)) {
        std::cerr << "Failed to get serial port state" << std::endl;
        CloseHandle(hSerial);
        return 1;
    }

    dcbSerialParams.BaudRate = CBR_115200;
    dcbSerialParams.ByteSize = 8;
    dcbSerialParams.StopBits = ONESTOPBIT;
    dcbSerialParams.Parity = NOPARITY;

    if (!SetCommState(hSerial, &dcbSerialParams)) {
        std::cerr << "Failed to set serial port state" << std::endl;
        CloseHandle(hSerial);
        return 1;
    }

    char buffer[256]; // Buffer to hold received data
    DWORD bytesRead;  // Variable to store the number of bytes read

    // Open a file for writing
    std::ofstream outputFile("C:\\Users\\godde\\Desktop\\received_data.txt");

    if (!outputFile.is_open()) {
        std::cerr << "Failed to open output file" << std::endl;
        CloseHandle(hSerial);
        return 1;
    }

    while (true) {
        if (ReadFile(hSerial, buffer, sizeof(buffer), &bytesRead, NULL)) {
            if (bytesRead > 0) {
                std::cout.write(buffer, bytesRead);

                // Write the received data to the file and immediately flush the buffer
                outputFile.write(buffer, bytesRead);
                outputFile.flush(); // Flush the buffer to ensure data is written immediately
            }
        }
        else {
            std::cerr << "Error reading from serial port" << std::endl;
            break;
        }
    }

    // Close the file before exiting
    outputFile.close();

    CloseHandle(hSerial);

    return 0;
}
