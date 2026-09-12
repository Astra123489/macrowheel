#pragma once

#include <QByteArray>
#include <QString>

class SchemaValidator
{
public:
    static bool validate(const QByteArray& jsonData);
    static QString lastError();
    
private:
    static QString s_lastError;
};