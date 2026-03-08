
import React from 'react';

interface SummaryCardProps {
  title: string;
  value: number | string;
  color: 'blue' | 'green' | 'yellow' | 'red' | 'purple' | 'orange';
  icon?: React.ReactNode;
}

const colorClasses = {
  blue: 'border-blue-500/50',
  green: 'border-green-500/50',
  yellow: 'border-yellow-500/50',
  red: 'border-red-500/50',
  purple: 'border-purple-500/50',
  orange: 'border-orange-500/50',
};

const SummaryCard: React.FC<SummaryCardProps> = ({ title, value, color, icon }) => {
  return (
    <div className={`bg-gray-800 p-5 rounded-lg shadow-md border-l-4 ${colorClasses[color]}`}>
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-400">{title}</h3>
        {icon && <div className="text-gray-500">{icon}</div>}
      </div>
      <p className="mt-2 text-3xl font-semibold text-gray-100">{value}</p>
    </div>
  );
};

export default SummaryCard;
