import * as React from "react";
import { cn } from "@/lib/utils";

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  hint?: string;
}

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, label, error, hint, id, ...props }, ref) => {
    const generatedId = React.useId();
    const inputId = id ?? generatedId;
    return (
      <div className="space-y-1.5">
        {label && (
          <label
            htmlFor={inputId}
            className="block text-xs font-medium text-[#A7B0BE]"
          >
            {label}
          </label>
        )}
        <input
          id={inputId}
          ref={ref}
          className={cn(
            "flex h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-3 py-2 text-sm text-[#F2F4F8] placeholder:text-[#778292] transition-colors focus:border-[#4B83F5] focus:bg-[#101318]/90 focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25 disabled:cursor-not-allowed disabled:opacity-50",
            error && "border-[#E56B72] focus:border-[#E56B72] focus:ring-[#E56B72]/25",
            className
          )}
          {...props}
        />
        {error ? (
          <p className="text-xs text-[#E56B72]">{error}</p>
        ) : hint ? (
          <p className="text-xs text-[#778292]">{hint}</p>
        ) : null}
      </div>
    );
  }
);
Input.displayName = "Input";

export interface SelectProps extends React.SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  error?: string;
}

export const Select = React.forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, label, error, id, children, ...props }, ref) => {
    const generatedId = React.useId();
    const selectId = id ?? generatedId;
    return (
      <div className="space-y-1.5">
        {label && (
          <label
            htmlFor={selectId}
            className="block text-xs font-medium text-[#A7B0BE]"
          >
            {label}
          </label>
        )}
        <select
          id={selectId}
          ref={ref}
          className={cn(
            "flex h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 px-3 py-2 text-sm text-[#F2F4F8] transition-colors focus:border-[#4B83F5] focus:bg-[#101318]/90 focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25 disabled:cursor-not-allowed disabled:opacity-50",
            error && "border-[#E56B72] focus:border-[#E56B72] focus:ring-[#E56B72]/25",
            className
          )}
          {...props}
        >
          {children}
        </select>
        {error && <p className="text-xs text-[#E56B72]">{error}</p>}
      </div>
    );
  }
);
Select.displayName = "Select";
