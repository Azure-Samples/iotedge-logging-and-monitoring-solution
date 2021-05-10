import os
import sys
import pytz
import logging
import datetime
from enum import Enum

class CustomLogFormatter(logging.Formatter):
    def formatException(self, exc_info):
        result = super().formatException(exc_info)
        return repr(result)

    def convertToSyslog(self, record: logging.LogRecord):
        """
        Convert pythong logging log levels to syslog standard. You can compare both using the following links:
        https://en.wikipedia.org/wiki/Syslog#Severity_level
        https://docs.python.org/3/howto/logging.html#logging-levels
        """

        if record.levelno == logging.DEBUG:
            record.levelno = 7
            record.levelname = "DBG"
        if record.levelno == logging.INFO:
            record.levelno = 6
            record.levelname = "INF"
        if record.levelno == logging.WARNING:
            record.levelno = 4
            record.levelname = "WRN"
        if record.levelno == logging.ERROR:
            record.levelno = 3
            record.levelname = "ERR"
        if record.levelno == logging.CRITICAL:
            record.levelno = 2
            record.levelname = "CRIT"
        
        return record

    def format(self, record, convert_to_syslog=True):
        if convert_to_syslog:
            record = self.convertToSyslog(record)

        result = super().format(record)
        if record.exc_text:
            result = result.replace("\n", "")

        return result

    def converter(self, timestamp):
        dt = datetime.datetime.fromtimestamp(timestamp)
        tzinfo = pytz.timezone('GMT')
        return tzinfo.localize(dt)

    def formatTime(self, record, datefmt=None, timespec='milliseconds'):
        dt = self.converter(record.created)
        if datefmt:
            s = dt.strftime(datefmt)
        else:
            try:
                s = dt.isoformat(' ', timespec=timespec)
            except TypeError:
                s = dt.isoformat()
            s = s.replace('+', ' +')
        return s

def CustomLogger(
    level: str="DEBUG",
    format: str='<%(levelno)s> %(asctime)s [%(levelname)s] %(message)s'):

    logger = logging.getLogger(__name__)
    logger.setLevel(getattr(logging, level))

    # create console handler
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(level)

    # configure formatter
    formatter = CustomLogFormatter(format)
    console.setFormatter(formatter)
    logger.addHandler(console)

    return logger